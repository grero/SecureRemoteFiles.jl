module RemoteFiles

const lib = "/usr/local/lib/libssh.dylib"
const lib2 = "src/remote_files.dylib"

mutable struct SSHSession
end

mutable struct SFTPSession
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

end # module
