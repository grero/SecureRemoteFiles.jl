using RemoteFiles
using Test

@testset "session" begin
    open("/tmp/testfile.txt","w") do f
        write(f, "This is a test")
    end
    data = RemoteFiles.ssh_session("localhost", 22) do session
        RemoteFiles.sftp_session(session) do sftp_session
            RemoteFiles.sftp_open(sftp_session, "/tmp/testfile.txt", 0) do file
                bytes = RemoteFiles.sftp_read(file, 100)
            end
        end
    end
    @test data == UInt8[0x54, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20, 0x61, 0x20, 0x74, 0x65, 0x73, 0x74, 0x0a]
    rm("/tmp/testfile.txt")
end
