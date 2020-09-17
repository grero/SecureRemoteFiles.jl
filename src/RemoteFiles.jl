module RemoteFiles
using JLD2

const lib = "/usr/local/lib/libssh.dylib"
const lib2 = "deps/remote_files.dylib"

mutable struct SSHSession
end

mutable struct SFTPSession
end

mutable struct SFTPFileHandle
end

mutable struct SFTPAttributes
end

mutable struct SFTPFile <: IO
    handle::Ptr{SFTPFileHandle}
    _isopen::Bool
end

include("dataio.jl")
include("buffered.jl")
include("jld2.jl")

function ssh_version()
    _version = ccall((:ssh_version, lib), Ptr{UInt8}, (Cint,), 0)
    vstring = unsafe_string(_version)
    return vstring
end

function ssh_session(hostname::String, port::Int64=22)
    session = ccall((:connect_to_host, lib2), Ptr{SSHSession}, (Cstring, Cint), hostname, port)
    if session == C_NULL
        error("Could not connect to host")
    end
    return session
end

function ssh_session(func::Function, hostname::String, port::Int64)
    session = ssh_session(hostname, port)
    try
        func(session)
    finally
        disconnect(session)
    end
end

function disconnect(session::Ptr{SSHSession})
    ccall((:disconnect, lib2), Cint, (Ptr{SSHSession},), session)
end

function sftp_session(ssh_session::Ptr{SSHSession})
    session = ccall((:sftp_new, lib2), Ptr{SFTPSession}, (Ptr{SSHSession},), ssh_session)
    if session == C_NULL
        error("Could not create SFTP session")
    end
    rc = ccall((:sftp_init, lib2), Cint, (Ptr{SFTPSession},), session)
    if rc != 0
        ccall((:sftp_free, lib2), Cvoid, (Ptr{SFTPSession},), session)
        error("Could not initialize session")
    end
    session
end

function disconnect(session::Ptr{SFTPSession})
    ccall((:sftp_free, lib2), Cvoid, (Ptr{SFTPSession},), session)
end

function sftp_session(func::Function, ssh_session)
    _sftp_session = sftp_session(ssh_session)
    try
        func(_sftp_session)
    finally
        disconnect(_sftp_session)
    end
end

function sftp_open(session::Ptr{SFTPSession}, fname::String, access_type::Int64)
    file = ccall((:sftp_open, lib2),Ptr{SFTPFileHandle}, (Ptr{SFTPSession}, Cstring, Cint), session, fname, access_type)
    if file == C_NULL
        error("Could not open remote file $fname")
    end
    return file
end

function sftp_close(file::Ptr{SFTPFileHandle})
    rc = ccall((:sftp_close, lib2), Cint, (Ptr{SFTPFileHandle},), file)
    if rc != 0
        error("Could not close remote file")
    end
end

function sftp_open(func::Function, sftp_session::Ptr{SFTPSession}, fname, access)
    file = sftp_open(sftp_session, fname, access)
    try
        func(file)
    finally
        sftp_close(file)
    end
end

function sftp_read(file::Ptr{SFTPFileHandle},nbytes::Int64)
    buffer = fill(zero(UInt8), nbytes)
    sftp_read(file, buffer)
end

function sftp_read(file::Ptr{SFTPFileHandle}, buffer::Vector{UInt8})
    nbytes = length(buffer)
    bytes_read = ccall((:sftp_read, lib), Cint, (Ptr{SFTPFileHandle}, Ref{UInt8}, Cint), file, buffer, nbytes)
    if bytes_read == 0
        return UInt8[]
    end
    return buffer[1:bytes_read]
end

function sftp_seek(file::Ptr{SFTPFileHandle}, pos::UInt64)
    rc = ccall((:sftp_seek, lib), Cint, (Ptr{SFTPFileHandle}, Culonglong), file, pos)
    if rc != 0
        error("Failed to seek to desired position")
    end
end

function sftp_tell(file::Ptr{SFTPFileHandle})
    pos = ccall((:sftp_tell64, lib), Culonglong, (Ptr{SFTPFileHandle},), file)
    return pos
end

Base.seek(file::SFTPFile, pos) = sftp_seek(file.handle, UInt64(pos))
Base.read!(file::SFTPFile, data::Vector{UInt8}) = sftp_read(file.handle, data)
Base.read(file::SFTPFile, ::Type{UInt8}) = (c = sftp_read(file.handle, 1); length(c) == 1 ? first(c) : nothing)
Base.close(file::SFTPFile) = (file._isopen && sftp_close(file.handle);file._isopen = false)
Base.isopen(file::SFTPFile) = file._isopen

# this is a hack
function Base.eof(file::SFTPFile)
    buffer = Vector{UInt8}(undef, 1) 
    n = sftp_read(file.handle, buffer)
    if n == 0
        return true
    else
        pos = sftp_tell(file.handle)
        sftp_seek(file.handle, pos-1)
    end
end

function readuntil(s::SFTPFile, delim::T; keep::Bool=false) where T
    out = (T === UInt8 ? Base.StringVector(0) : Vector{T}())
    while true
        c = read(s, T)
        if c == delim
            keep && push!(out, c)
            break
        elseif c == nothing
            break
        end
        push!(out, c)
    end
    return out
end

function sftp_fstat(file::Ptr{SFTPFileHandle})
    _fstat = ccall((:sftp_fstat, lib), Ptr{SFTPAttributes}, (Ptr{SFTPFileHandle},), file)
    if _fstat == C_NULL
        error("Could not get fstats for file")
    end
    return _fstat
end

function Base.stat(io::SFTPFile)
    fstat = sftp_fstat(io.handle)
    bufptr = convert(Ptr{UInt8}, _fstat)
    bytes = Vector{UInt8}(undef, 8)
    for i in 1:length(bytes) 
        bytes[i] = unsafe_load(bufptr, 24+i)
    end
    fsize = first(reinterpret(UInt64, bytes))
end

function sftp_filesize(file::Ptr{SFTPFileHandle})
    _fstat = sftp_fstat(file)
    bufptr = convert(Ptr{UInt8}, _fstat)
    bytes = Vector{UInt8}(undef, 8)
    for i in 1:length(bytes) 
        bytes[i] = unsafe_load(bufptr, 24+i)
    end
    fsize = reinterpret(UInt64, bytes)
    first(fsize)
end

function sftp_filename(file::Ptr{SFTPFileHandle})
    _fstat = sftp_fstat(file)
    bufptr = unsafe_load(convert(Ptr{UInt64}, _fstat),2)
    @show bufptr
    name = unsafe_string(convert(Ptr{UInt8}, bufptr[1]))
    return name
end

function Base.filesize(io::SFTPFile)
    sftp_filesize(io.handle)
end

function Base.position(io::SFTPFile)
    sftp_tell(io.handle)
end

# reads are always blocking for now
Base.bytesavailable(io::SFTPFile) = 0

end # module
