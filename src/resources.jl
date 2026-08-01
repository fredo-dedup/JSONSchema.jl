# Copyright (c) 2026: fredo-dedup, quinnj, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

"""Generic, non-mutating JSON resource identification and lookup."""
module Resources

import ..URIs

struct PointerError <: Exception
    pointer::String
    token::Int
    reason::String
end

function Base.showerror(io::IO, err::PointerError)
    location = err.token == 0 ? "root" : "token $(err.token)"
    return print(io, "invalid JSON Pointer ", repr(err.pointer), " at ", location, ": ", err.reason)
end

"""A parsed RFC 6901 JSON Pointer."""
struct JSONPointer
    tokens::Tuple{Vararg{String}}
end

JSONPointer() = JSONPointer(())

function _unescape_token(token::AbstractString, pointer::AbstractString, index::Int)
    i = firstindex(token)
    last = lastindex(token)
    io = IOBuffer()
    while i <= last
        char = token[i]
        if char != '~'
            write(io, char)
            i = nextind(token, i)
            continue
        end
        next = nextind(token, i)
        if next > last || !(token[next] in ('0', '1'))
            throw(PointerError(String(pointer), index, "invalid '~' escape"))
        end
        write(io, token[next] == '0' ? '~' : '/')
        i = nextind(token, next)
    end
    return String(take!(io))
end

function JSONPointer(pointer::AbstractString)
    isempty(pointer) && return JSONPointer()
    startswith(pointer, '/') ||
        throw(PointerError(String(pointer), 0, "a non-empty pointer must start with '/'"))
    raw = split(SubString(pointer, nextind(pointer, firstindex(pointer))), '/'; keepempty = true)
    tokens = ntuple(length(raw)) do i
        return _unescape_token(raw[i], pointer, i)
    end
    return JSONPointer(tokens)
end

function _escape_token(token::String)
    return replace(replace(token, "~" => "~0"), "/" => "~1")
end

function Base.string(pointer::JSONPointer)
    isempty(pointer.tokens) && return ""
    return "/" * join((_escape_token(token) for token in pointer.tokens), "/")
end

Base.show(io::IO, pointer::JSONPointer) = print(io, "JSONPointer(", repr(string(pointer)), ")")
Base.length(pointer::JSONPointer) = length(pointer.tokens)
Base.isempty(pointer::JSONPointer) = isempty(pointer.tokens)
Base.iterate(pointer::JSONPointer, state...) = iterate(pointer.tokens, state...)
Base.getindex(pointer::JSONPointer, index::Integer) = pointer.tokens[index]

function Base.:/(pointer::JSONPointer, token::AbstractString)
    return JSONPointer((pointer.tokens..., String(token)))
end

struct FrozenObject <: AbstractDict{String,Any}
    entries::Vector{Pair{String,Any}}
end

Base.IteratorSize(::Type{<:FrozenObject}) = Base.HasLength()
Base.length(object::FrozenObject) = length(object.entries)
Base.iterate(object::FrozenObject, state...) = iterate(object.entries, state...)
Base.copy(object::FrozenObject) = object

function Base.haskey(object::FrozenObject, key)
    return any(entry -> isequal(entry.first, key), object.entries)
end

function Base.getindex(object::FrozenObject, key)
    for entry in object.entries
        isequal(entry.first, key) && return entry.second
    end
    throw(KeyError(key))
end

struct FrozenArray <: AbstractVector{Any}
    entries::Vector{Any}
end

Base.IndexStyle(::Type{FrozenArray}) = IndexLinear()
Base.size(array::FrozenArray) = size(array.entries)
Base.getindex(array::FrozenArray, index::Int) = array.entries[index]
Base.copy(array::FrozenArray) = array

"""Create a read-only recursive view of a parsed JSON value."""
freeze(value::FrozenObject) = value
freeze(value::FrozenArray) = value

function freeze(value::AbstractDict)
    entries = Pair{String,Any}[]
    sizehint!(entries, length(value))
    for (key, item) in value
        key isa AbstractString || throw(ArgumentError("JSON object keys must be strings"))
        push!(entries, String(key) => freeze(item))
    end
    return FrozenObject(entries)
end

function freeze(value::AbstractVector)
    entries = Any[]
    sizehint!(entries, length(value))
    for item in value
        push!(entries, freeze(item))
    end
    return FrozenArray(entries)
end

freeze(value) = value

function _array_index(pointer::JSONPointer, token::String, index::Int)
    isempty(token) &&
        throw(PointerError(string(pointer), index, "an array index cannot be empty"))
    token == "0" || !startswith(token, '0') ||
        throw(PointerError(string(pointer), index, "an array index cannot have a leading zero"))
    value = tryparse(Int, token)
    value === nothing &&
        throw(PointerError(string(pointer), index, "expected a non-negative integer array index"))
    value < 0 &&
        throw(PointerError(string(pointer), index, "expected a non-negative integer array index"))
    return value + 1
end

function resolve(document, pointer::JSONPointer)
    value = document
    for (index, token) in enumerate(pointer.tokens)
        if value isa AbstractDict
            haskey(value, token) ||
                throw(PointerError(string(pointer), index, "object member $(repr(token)) does not exist"))
            value = value[token]
        elseif value isa AbstractVector
            julia_index = _array_index(pointer, token, index)
            checkbounds(Bool, value, julia_index) ||
                throw(PointerError(string(pointer), index, "array index $(repr(token)) is out of bounds"))
            value = value[julia_index]
        else
            throw(PointerError(string(pointer), index, "cannot traverse a $(typeof(value)) value"))
        end
    end
    return value
end

"""A canonical, fragment-free resource identifier."""
struct ResourceId
    uri::URIs.URI
    text::String

    function ResourceId(uri::URIs.URI)
        isempty(uri.fragment) || throw(ArgumentError("a resource identifier cannot contain a fragment"))
        normalized = _build_uri(
            lowercase(uri.scheme),
            uri.userinfo,
            lowercase(uri.host),
            _normalized_port(uri.scheme, uri.port),
            uri.path,
            uri.query,
        )
        return new(normalized, string(normalized))
    end
end

function _build_uri(scheme, userinfo, host, port, path, query)
    if isempty(port)
        return URIs.URI(; scheme, userinfo, host, path, query)
    end
    return URIs.URI(; scheme, userinfo, host, port, path, query)
end

function _normalized_port(scheme::AbstractString, port::AbstractString)
    normalized_scheme = lowercase(scheme)
    if (normalized_scheme == "http" && port == "80") ||
       (normalized_scheme == "https" && port == "443")
        return ""
    end
    return String(port)
end

ResourceId(uri::AbstractString) = ResourceId(URIs.URI(uri))
Base.string(id::ResourceId) = id.text
Base.:(==)(left::ResourceId, right::ResourceId) = left.text == right.text
Base.isequal(left::ResourceId, right::ResourceId) = isequal(left.text, right.text)
Base.hash(id::ResourceId, hash::UInt) = Base.hash(id.text, hash)
Base.show(io::IO, id::ResourceId) = print(io, "ResourceId(", repr(string(id)), ")")

abstract type Fragment end

struct RootFragment <: Fragment end

struct PointerFragment <: Fragment
    pointer::JSONPointer
end

struct AnchorFragment <: Fragment
    name::String

    function AnchorFragment(name::AbstractString)
        isempty(name) && throw(ArgumentError("an anchor name cannot be empty"))
        return new(String(name))
    end
end

"""An absolute resource reference with a parsed root, pointer, or anchor fragment."""
struct Reference
    resource::ResourceId
    fragment::Fragment
end

function _without_fragment(uri::URIs.URI)
    return _build_uri(uri.scheme, uri.userinfo, uri.host, uri.port, uri.path, uri.query)
end

function _fragment(uri::URIs.URI)
    fragment = URIs.unescapeuri(uri.fragment)
    isempty(fragment) && return RootFragment()
    startswith(fragment, '/') && return PointerFragment(JSONPointer(fragment))
    return AnchorFragment(fragment)
end

function Reference(base::ResourceId, reference::AbstractString)
    resolved = URIs.resolvereference(base.uri, URIs.URI(reference))
    return Reference(ResourceId(_without_fragment(resolved)), _fragment(resolved))
end

struct NodeId
    resource::ResourceId
    pointer::JSONPointer
end

"""A read-only JSON resource with canonical and retrieval identifiers."""
struct Resource{T}
    id::ResourceId
    retrieval::ResourceId
    contents::T
    media_type::Union{Nothing,String}
end

function Resource(
    id::ResourceId,
    contents;
    retrieval::ResourceId = id,
    media_type::Union{Nothing,AbstractString} = nothing,
)
    frozen = freeze(contents)
    normalized_media_type = media_type === nothing ? nothing : String(media_type)
    return Resource(id, retrieval, frozen, normalized_media_type)
end

struct DuplicateResourceError <: Exception
    id::ResourceId
end

function Base.showerror(io::IO, err::DuplicateResourceError)
    return print(io, "resource ", repr(string(err.id)), " is already registered")
end

struct MissingResourceError <: Exception
    id::ResourceId
end

function Base.showerror(io::IO, err::MissingResourceError)
    return print(io, "resource ", repr(string(err.id)), " is not registered")
end

struct MissingAnchorError <: Exception
    resource::ResourceId
    anchor::String
end

function Base.showerror(io::IO, err::MissingAnchorError)
    return print(
        io,
        "anchor ",
        repr(err.anchor),
        " is not registered in resource ",
        repr(string(err.resource)),
    )
end

"""A registry of immutable resources, aliases, and plain-name anchors."""
mutable struct Registry
    resources::Dict{ResourceId,Resource}
    aliases::Dict{ResourceId,ResourceId}
    anchors::Dict{Tuple{ResourceId,String},NodeId}
end

Registry() = Registry(
    Dict{ResourceId,Resource}(),
    Dict{ResourceId,ResourceId}(),
    Dict{Tuple{ResourceId,String},NodeId}(),
)

function _canonical_id(registry::Registry, id::ResourceId)
    return get(registry.aliases, id, id)
end

function register!(
    registry::Registry,
    resource::Resource;
    aliases = ResourceId[],
    anchors = Pair{String,JSONPointer}[],
)
    ids = ResourceId[resource.id, resource.retrieval]
    append!(ids, aliases)
    unique!(ids)
    for id in ids
        canonical = _canonical_id(registry, id)
        if haskey(registry.resources, canonical) || haskey(registry.aliases, id)
            throw(DuplicateResourceError(id))
        end
    end
    anchor_entries = Pair{Tuple{ResourceId,String},NodeId}[]
    for (name, pointer) in anchors
        normalized_name = AnchorFragment(name).name
        key = (resource.id, normalized_name)
        if haskey(registry.anchors, key) || any(entry -> entry.first == key, anchor_entries)
            throw(ArgumentError("duplicate anchor $(repr(normalized_name))"))
        end
        resolve(resource.contents, pointer)
        push!(anchor_entries, key => NodeId(resource.id, pointer))
    end
    registry.resources[resource.id] = resource
    for id in ids
        id == resource.id && continue
        registry.aliases[id] = resource.id
    end
    for entry in anchor_entries
        registry.anchors[entry.first] = entry.second
    end
    return resource
end

function resource(registry::Registry, id::ResourceId)
    canonical = _canonical_id(registry, id)
    return get(() -> throw(MissingResourceError(id)), registry.resources, canonical)
end

struct ResolvedNode{T}
    id::NodeId
    value::T
end

function resolve(registry::Registry, reference::Reference)
    registered = resource(registry, reference.resource)
    fragment = reference.fragment
    if fragment isa RootFragment
        id = NodeId(registered.id, JSONPointer())
    elseif fragment isa PointerFragment
        id = NodeId(registered.id, fragment.pointer)
    else
        key = (registered.id, fragment.name)
        id = get(() -> throw(MissingAnchorError(registered.id, fragment.name)), registry.anchors, key)
    end
    return ResolvedNode(id, resolve(registered.contents, id.pointer))
end

end
