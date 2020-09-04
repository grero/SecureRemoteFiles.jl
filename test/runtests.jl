using RemoteFiles
using Test

@testset "session" begin
    session = RemoteFiles.ssh_session()
    open(session, "cortex.nus.edu.sg", "workingmemory", 9469)
    RemoteFiles.connect(session)
    RemoteFiles.disconnect(session)
    RemoteFiles.free(session)
end
