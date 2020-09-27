@inline function JLD2.read_scalar(f::JLD2.JLDFile{SFTPFile}, rr, header_offset::JLD2.RelOffset)
    r = Vector{UInt8}(undef, JLD2.odr_sizeof(rr))
    @GC.preserve r begin
        unsafe_read(f.io, pointer(r), JLD2.odr_sizeof(rr))
        JLD2.jlconvert(rr, f, pointer(r), header_offset)
    end
end

@inline function JLD2.read_array!(v::Array{T}, f::JLD2.JLDFile{SFTPFile},
                             rr::JLD2.ReadRepresentation{T,T}) where T
    unsafe_read(f.io, pointer(v), JLD2.odr_sizeof(T)*length(v))
    v
end
