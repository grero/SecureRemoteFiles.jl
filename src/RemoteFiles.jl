module RemoteFiles

const lib = "/usr/local/lib/libssh.dylib"
const lib2 = "deps/remote_files.dylib"

mutable struct SSHSession
end

mutable struct SFTPSession
end

mutable struct SFTPFile <: IO
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
    file = ccall((:sftp_open, lib2),Ptr{SFTPFile}, (Ptr{SFTPSession}, Cstring, Cint), session, fname, access_type)
    if file == C_NULL
        error("Could not open remote file $fname")
    end
    return file
end

function sftp_close(file::Ptr{SFTPFile})
    rc = ccall((:sftp_close, lib2), Cint, (Ptr{SFTPFile},), file)
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

function sftp_read(file::Ptr{SFTPFile},nbytes::Int64)
    buffer = fill(zero(UInt8), nbytes)
    bytes_read = ccall((:sftp_read, lib), Cint, (Ptr{SFTPFile}, Ref{UInt8}, Cint), file, buffer, nbytes)
    if bytes_read == 0
        return UInt8[]
    end
    return buffer[1:bytes_read]
end

function sftp_seek(file::Ptr{SFTPFile}, pos::Int64)
    rc = ccall((:sftp_seek, lib), Cint, (Ptr{SFTPFile}, Cint), file, pos)
    if rc != 0
        error("Failed to seek to desired position")
    end
end

end # module
