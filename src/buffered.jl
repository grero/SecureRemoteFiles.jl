const Plain = Union{Int16,Int32,Int64,Int128,UInt16,UInt32,UInt64,UInt128,Float16,Float32,
                    Float64}
const PlainType = Union{Type{Int16},Type{Int32},Type{Int64},Type{Int128},Type{UInt16},
                        Type{UInt32},Type{UInt64},Type{UInt128},Type{Float16},
                        Type{Float32},Type{Float64}}
const DEFAULT_BUFFER_SIZE = 1024

struct BufferedSFTPWriter <: IO
    f::SFTPFile
    buffer::Vector{UInt8}
    file_position::Int64
    position::Base.RefValue{Int}
end

function BufferedSFTPWriter(io::SFTPFile, buffer_size::Int)
    pos = position(io)
    skip(io, buffer_size)
    BufferedSFTPWriter(io, Vector{UInt8}(undef, buffer_size), pos, Ref{Int}(0))
end
Base.show(io::IO, ::BufferedSFTPWriter) = print(io, "BufferedSFTPWriter")

function finish!(io::BufferedSFTPWriter)
    f = io.f
    buffer = io.buffer
    io.position[] == length(buffer) ||
        error("buffer not written to end; position is $(io.position[]) but length is $(length(buffer))")
    seek(f, io.file_position)
    write(f, buffer)
    io.position[] = 0
    nothing
end

@inline function _write(io::BufferedSFTPWriter, x)
    position = io.position[]
    buffer = io.buffer
    n = sizeof(x)
    n + position <= length(buffer) || throw(EOFError())
    io.position[] = position + n
    unsafe_store!(Ptr{typeof(x)}(pointer(buffer, position+1)), x)
    # Base.show_backtrace(STDOUT, backtrace())
    # gc()
    return n
end
@inline Base.write(io::BufferedSFTPWriter, x::UInt8) = _write(io, x)
@inline Base.write(io::BufferedSFTPWriter, x::Int8) = _write(io, x)
@inline Base.write(io::BufferedSFTPWriter, x::Plain)  = _write(io, x)

function Base.unsafe_write(io::BufferedSFTPWriter, x::Ptr{UInt8}, n::UInt64)
    buffer = io.buffer
    position = io.position[]
    n + position <= length(buffer) || throw(EOFError())
    unsafe_copyto!(pointer(buffer, position+1), x, n)
    io.position[] = position + n
    # Base.show_backtrace(STDOUT, backtrace())
    # gc()
    return n
end

Base.position(io::BufferedSFTPWriter) = io.file_position + io.position[]

struct BufferedSFTPReader <: IO
    f::SFTPFile
    buffer::Vector{UInt8}
    file_position::Int64
    position::Base.RefValue{Int}
end

BufferedSFTPReader(io::SFTPFile) = 
    BufferedSFTPReader(io, Vector{UInt8}(), position(io), Ref{Int}(0))
Base.show(io::IO, ::BufferedSFTPReader) = print(io, "BufferedSFTPReader")

function readmore!(io::BufferedSFTPReader, n::Int)
    f = io.f
    amount = max(bytesavailable(f), n)
    buffer = io.buffer
    oldlen = length(buffer)
    resize!(buffer, oldlen + amount)
    unsafe_read(f, pointer(buffer, oldlen+1), amount)
end

@inline function _read(io::BufferedSFTPReader, T::DataType)
    position = io.position[]
    buffer = io.buffer
    if length(buffer) - position < sizeof(T)
        readmore!(io, sizeof(T))
    end
    io.position[] = position + sizeof(T)
    unsafe_load(Ptr{T}(pointer(buffer, position+1)))
end
@inline Base.read(io::BufferedSFTPReader, T::Type{UInt8}) = _read(io, T)
@inline Base.read(io::BufferedSFTPReader, T::Type{Int8}) = _read(io, T)
@inline Base.read(io::BufferedSFTPReader, T::PlainType) = _read(io, T)

function Base.read(io::BufferedSFTPReader, ::Type{T}, n::Int) where T
    position = io.position[]
    buffer = io.buffer
    n = sizeof(T) * n
    if length(buffer) - position < n
        readmore!(io, sizeof(T))
    end
    io.position[] = position + n
    arr = Vector{T}(undef, n)
    unsafe_copyto!(pointer(arr), Ptr{T}(pointer(buffer, position+1)), n)
    arr
end
Base.read(io::BufferedSFTPReader, ::Type{T}, n::Integer) where {T} =
    read(io, T, Int(n))

Base.position(io::BufferedSFTPReader) = io.file_position + io.position[]

function adjust_position!(io::BufferedSFTPReader, position::Integer)
    if position < 0
        throw(ArgumentError("cannot seek before start of buffer"))
    elseif position > length(io.buffer)
        readmore!(io, position - length(io.buffer))
    end
    io.position[] = position
end

Base.seek(io::BufferedSFTPReader, offset::Integer) =
    adjust_position!(io, offset - io.file_position)

Base.skip(io::BufferedSFTPReader, offset::Integer) =
    adjust_position!(io, io.position[] + offset)

finish!(io::BufferedSFTPReader) =
    seek(io.f, io.file_position + io.position[])

function truncate_and_close(io::IOStream, endpos::Integer)
    truncate(io, endpos)
    close(io)
end


# We sometimes need to compute checksums. We do this by first calling begin_checksum when
# starting to handle whatever needs checksumming, and calling end_checksum afterwards. Note
# that we never compute nested checksums, but we may compute multiple checksums
# simultaneously.

function JLD2.begin_checksum_read(io::SFTPFile)
    BufferedSFTPReader(io)
end
function JLD2.begin_checksum_write(io::SFTPFile, sz::Integer)
    BufferedSFTPWriter(io, sz)
end
function JLD2.end_checksum(io::Union{BufferedSFTPReader,BufferedSFTPWriter})
    ret = JLD2.Lookup3.hash(io.buffer, 1, io.position[])
    finish!(io)
    ret
end
