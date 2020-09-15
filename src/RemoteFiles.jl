module RemoteFiles

const lib = "/usr/local/lib/libssh.dylib"
const lib2 = "src/remote_files.dylib"

mutable struct SSHSession
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

end # module
