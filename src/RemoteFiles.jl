module RemoteFiles

const lib = "/usr/local/lib/libssh.dylib"

mutable struct SSHSession
end

@enum SSHOption  SSH_OPTIONS_HOST=0 SSH_OPTIONS_PORT=1 SSH_OPTIONS_PORT_STR=2 SSH_OPTIONS_FD=3 SSH_OPTIONS_USER=4

function ssh_session() 
    output_ptr = ccall((:ssh_new, lib), Ptr{SSHSession}, ())
    if output_ptr == C_NULL 
        throw(error("Could no create session"))
      end
    return output_ptr
end

function Base.open(session::Ref{SSHSession}, hostname::String, username::String, port::Int64=22)
    ccall((:ssh_options_set, lib), Cint, (Ref{SSHSession},Cint, Cstring), session, SSH_OPTIONS_HOST, hostname)    
    ccall((:ssh_options_set, lib), Cint, (Ref{SSHSession},Cint, Cstring), session, SSH_OPTIONS_USER, username)    
    ccall((:ssh_options_set, lib), Cint, (Ref{SSHSession},Cint, Ref{Cint}), session, SSH_OPTIONS_PORT, port)    
end

function connect(session::Ref{SSHSession})
    ccall((:ssh_connect, lib), Cint, (Ref{SSHSession},), session)
end

function disconnect(session::Ref{SSHSession})
    ccall((:ssh_disconnect, lib), Cint, (Ref{SSHSession},), session)
end

function free(session::Ref{SSHSession})
    ccall((:ssh_free, lib), Cvoid, (Ref{SSHSession},), session)
end

end # module
