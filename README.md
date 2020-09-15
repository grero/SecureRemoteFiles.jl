# RemoteFiles
A tool to read (parts of) remote files using ssh/sfp.

## Usage

```julia
using RemoteFiles
RemoteFiles.ssh_session("localhost") do session
    # run some code here
end
```
