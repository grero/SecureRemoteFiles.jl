using RemoteFiles
using Test
using JLD2

@testset "session" begin
    open("/tmp/testfile.txt","w") do f
        write(f, "This is a test")
    end
    fsize, data = RemoteFiles.ssh_session("localhost", 22) do session
        RemoteFiles.sftp_session(session) do sftp_session
            RemoteFiles.sftp_open(sftp_session, "/tmp/testfile.txt", 0) do file
                fsize = RemoteFiles.sftp_filesize(file)
            #    fname = RemoteFiles.sftp_filename(file)
            #    @show fname
                bytes = RemoteFiles.sftp_read(file, 100)
                fsize, bytes 
            end
        end
    end
    @test data == UInt8[0x54, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20, 0x61, 0x20, 0x74, 0x65, 0x73, 0x74]
    @test fsize == 0x000000000000000e
    rm("/tmp/testfile.txt")
end

@testset "JLD2" begin
    tdir = tempdir()
    cd(tdir) do
        a = 1
        b = [1,2,3]
        c = "hello"
        @save "test.jl2" a b c
    end
    ssh_session = RemoteFiles.ssh_session("localhost",22)
    sftp_session = RemoteFiles.sftp_session(ssh_session)
    try
        jfile = JLD2.jldopen(joinpath(tdir, "test.jl2"), false, false, false, RemoteFiles.SFTPFile, sftp_session, nothing, false, false)
        @test jfile["a"] == 1
        @test jfile["b"] == [1,2,3]
        @test jfile["c"] == "hello"
        @show jfile.written, jfile.n_times_opened
        # need to close everything now before the session closes
        JLD2.jld_finalizer(jfile)
    finally
        RemoteFiles.disconnect(sftp_session)
        RemoteFiles.disconnect(ssh_session)
    end
end
