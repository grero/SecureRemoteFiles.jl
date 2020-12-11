module RemoteFiles
using JLD2
using ProgressMeter
using Base: open

if "TRAVIS" in keys(ENV)
    const lib = "/usr/lib/x86_64-linux-gnu/libssh.so"
elseif Sys.isapple() || Sys.isunix()
    const lib = "/usr/local/lib/libssh.dylib"
end

const lib2 = joinpath(@__DIR__, "..", "deps", "remote_files.dylib")
const XFER_BUF_SIZE = 32767
const MB = 1048576

@enum SSHLogLevel nolog=0 warning=1 protocol=2 packet=3 functions=4

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

struct SFTPPath
    hostname::String
    username::String
    port::Int64
    path::String
end

function SFTPPath(ss::String)
    pattern = r"([[:alnum:]]+@)*([[:alnum:]]*)\:*([0-9]*)\:([[:alnum:][:punct:]]*)"
    m = match(pattern, ss)
    if m == nothing
        error("$ss is not a valid sftp path")
    end
    if m.captures[1] != nothing
        username = rstrip(m.captures[1], '@')
    else
        username = ""
    end
    hostname = m.captures[2]
    if !isempty(m.captures[3])
        port = parse(Int64, m.captures[3])
    else
        port = 22
    end
    path = m.captures[4]
    SFTPPath(hostname, username, port, path)
end

macro sftp_str(p)
    SFTPPath(p)
end

include("dataio.jl")
include("buffered.jl")
include("jld2.jl")

function ssh_version()
    _version = ccall((:ssh_version, lib), Ptr{UInt8}, (Cint,), 0)
    vstring = unsafe_string(_version)
    return vstring
end

function ssh_session(hostname::String, port::Int64=22, verbosity::SSHLogLevel=nolog)
    session = ccall((:connect_to_host, lib2), Ptr{SSHSession}, (Cstring, Cint, Cint), hostname, port, verbosity)
    if session == C_NULL
        error("Could not connect to host")
    end
    return session
end

function ssh_session(func::Function, hostname::String, port::Int64, verbosity::SSHLogLevel=nolog)
    session = ssh_session(hostname, port, verbosity)
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
        err = ccall((:ssh_get_error, lib), Ptr{UInt8}, (Ptr{SSHSession},), ssh_session)
        errmsg = unsafe_string(err)
        error("Could not create SFTP session. $(errmsg)")
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
        errcode = ccall((:sftp_get_error, lib), Cint, (Ptr{SFTPSession},), session)
        if errcode == 2
            # No such file, check if we are dealing with a symbolic link
            pathptr = ccall((:sftp_readlink, lib), Ptr{UInt8}, (Ptr{SFTPSession},Cstring),session, fname)
            if pathptr == C_NULL
                errcode = ccall((:sftp_get_error, lib), Cint, (Ptr{SFTPSession},), session)
                error("Could not open remote link $fname. Error was $errcode.")
            end
            _fname = unsafe_string(pathptr)
            if !isabspath(_fname)
                # relatove to filename
                _fname = joinpath(dirname(fname), _fname)
            end
            sftp_open(session, _fname, access_type)
        else
            error("Could not open remote file $fname. Error was $errcode.")
        end
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
    a = nothing
    try
        a = func(file)
    finally
        sftp_close(file)
    end
    a
end

function Base.open(func::Function, path::SFTPPath, perm, args...;kvs...)
    ssh_session(path.hostname, path.port) do session
        sftp_session(session) do _sftpsession
            sftp_open(_sftpsession, path.path, perm) do ff
                func(SFTPFile(ff, true), args...; kvs...)
            end
        end
    end
end

function Base.open(path::SFTPPath, perm=0)
    _session = ssh_session(path.hostname, path.port)
    _sftp_session = sftp_session(_session)
     ff = sftp_open(_sftp_session, path.path, perm)
     SFTPFile(ff, true)
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

function Base.unsafe_read(file::SFTPFile, p::Ptr{UInt8}, nbytes::UInt)
    #TODO: handle chunks here
    handle = file.handle
    to_read = nbytes
    offset = 0
    prog = Progress(nbytes, 1.0)
    while true
        nb = min(to_read, XFER_BUF_SIZE)
        t0 = time()
        bytes_read = ccall((:sftp_read, lib), Cssize_t, (Ptr{SFTPFileHandle},
                                         Ptr{UInt8}, Csize_t), handle, p+offset, nb)
        t1 = time()
        rate = (bytes_read/MB)/(t1-t0)
        t0 = t1
        rates = "$(round(rate, digits=1)) MB/s"
        if bytes_read < nb
            error("Could not read from file")
        end
        to_read = max(0, to_read - nb)
        to_reads = "$(round(to_read/MB, digits=1)) MB"
        offset += bytes_read
        update!(prog, offset;showvalues=[(:Remaining, to_reads),
                                         (:Rate, rates)])
        if to_read == 0
            break
        end
    end
    nothing
end

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
