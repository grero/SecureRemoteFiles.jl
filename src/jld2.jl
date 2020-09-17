using JLD2
using JLD2: verify_file_header, load_group, JLDFile

JLD2.read_bytestring(io::SFTPFile) = String(readuntil(io, 0x0))

function JLD2.openfile(::Type{SFTPFile}, session::Ptr{SFTPSession}, fname, wr, create, truncate, fallback::Nothing=nothing)
    access = 0
    sftp_open(session, fname, access)    
end

function JLD2.jldopen(fname::AbstractString, wr::Bool, create::Bool, truncate::Bool, ::Type{SFTPFile}, fallback=nothing, compress::Bool=false, mmaparrays::Bool=false, session::Ptr{SFPSession})
    # exist fname
    created = true
    io = openfile(SFTPFile, session, fname, wr, create, truncate, fallback)
    f = JLDFile(io, fname, wr, created, compress, mmaparrays)
    JLD2.OPEN_FILES[fname] = WeakRef(f)
    if created
        f.root_group = JLD2.Group{typeof(f)}(f)
        f.types_group = JLD2.Group{typeof(f)}(f)
    else
        verify_file_header(f)
        seek(io, JLD2.FILE_HEADER_LENGTH)
        superblock = read(io, Superblock)
    f.end_of_data = superblock.end_of_file_address
    f.root_group_offset = superblock.root_group_object_header_address
    f.root_group = load_group(f, superblock.root_group_object_header_address)
    end

end

