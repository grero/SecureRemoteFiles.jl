# RemoteFiles
A tool to read (parts of) remote files using ssh/sfp.

## Usage

```julia
using RemoteFiles
RemoteFiles.ssh_session("localhost") do session
    # run some code here
end
```

### JLD2 files
The primary motivation for this package was actually to avoid having to download large JLD2/HDF5 files when you only need a small part of that file. As an illustration, we can create the following file

```julia
using JLD2
Sw = randn(36,36,250,1000)
Sb = randn(36,36,250,1000)
perf = rand(250,250,1000)
@save "decoders.jl2" Sw Sb perf
```
In this eaxample `Sw` and `Sb` could be the estimated within-class and between-class scatter matrices in a multi-class LDA decoder, while `perf` is the performance of the decdoer. We imagine using 250 time bins, training and testing on each pair of time bins (so-called cross-temporal decoding), and randomly sampling training and testing sets 1000 times. In this case, `Sw` and `Sb` each take up about 2.4 GB of space, while `perf` only takes up about 466 MB. 
If, for some application, we are only interested in the `perf` variable, we can do:

```julia
using RemoteFles
perf = RemoteFiles.ssh_session(hostname, 22) do session
    RemoteFiles.sftp_session(session) do sftp_session
        RemoteFiles.jldopen("/tmp/decoders.jd2", false, false, false, RemoteFiles.SFTPFile, sftp_session, nothing, false, false) do jfile
           jfile["perf"]
        end
    end
end
```

and it takes only a fraction of the time it would take to download the entire file.
