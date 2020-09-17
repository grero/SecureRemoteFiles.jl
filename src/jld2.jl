using JLD2
using JLD2: verify_file_header, load_group, JLDFile

JLD2.read_bytestring(io::SFTPFile) = String(readuntil(io, 0x0))

function JLD2.openfile(::Type{SFTPFile}, session::Ptr{SFTPSession}, fname, wr, create, truncate, fallback::Nothing=nothing)
    access = 0
    handle = sftp_open(session, fname, access)
    SFTPFile(handle, true)
end

function JLD2.jldopen(fname::AbstractString, wr::Bool, create::Bool, truncate::Bool, ::Type{SFTPFile}, session::Ptr{SFTPSession},fallback=nothing, compress::Bool=false, mmaparrays::Bool=false)
    # exist fname
    created = false 
    io = JLD2.openfile(SFTPFile, session, fname, wr, create, truncate, fallback)
    f = JLDFile(io, fname, wr, created, compress, mmaparrays)
    JLD2.OPEN_FILES[fname] = WeakRef(f)
    f.n_times_opened = 1
    if created
        f.root_group = JLD2.Group{typeof(f)}(f)
        f.types_group = JLD2.Group{typeof(f)}(f)
    else
        verify_file_header(f)
        seek(io, JLD2.FILE_HEADER_LENGTH)
        superblock = read(io, JLD2.Superblock)
    f.end_of_data = superblock.end_of_file_address
    f.root_group_offset = superblock.root_group_object_header_address
    f.root_group = load_group(f, superblock.root_group_object_header_address)
    f
    end
end


function JLD2.jld_finalizer(f::JLD2.JLDFile{SFTPFile})
    f.n_times_opened == 0 && return
    if f.written && !isopen(f.io)
        f.io = openfile(SFTPFile, f.path, true, false, false)
    end
    f.n_times_opened = 1
    close(f)
end

