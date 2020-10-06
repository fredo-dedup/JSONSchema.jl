function type_to_dict(x)
    return Dict(name => getfield(x, name) for name in fieldnames(typeof(x)))
end

function update_id(uri::HTTP.URI, s::String)
    id2 = HTTP.URI(s)
    if !isempty(id2.scheme)
        return id2
    end
    els = type_to_dict(uri)
    delete!(els, :uri)
    els[:fragment] = id2.fragment
    if !isempty(id2.path)
        oldpath = match(r"^(.*/).*$", uri.path)
        els[:path] = oldpath === nothing ? id2.path : oldpath.captures[1] * id2.path
    end
    return HTTP.URI(; els...)
end

function get_remote_schema(uri::HTTP.URI)
    r = HTTP.get(uri)
    if r.status != 200
        error("Unable to get remote schema at $uri. HTTP status = $(r.status)")
    end
    return Schema(JSON.parse(String(r.body)))
end

function find_ref(
    uri::HTTP.URI, id_map::AbstractDict, path::String, parent_dir::String
)
    if path == "" || path == "#"  # This path refers to the root schema.
        return id_map[string(uri)]
    elseif startswith(path, "#/")  # This path is a JPointer.
        p = JSONPointer.Pointer(path; shift_index = true)
        return id_map[string(uri)][p]
    end
    uri = update_id(uri, path)
    els = type_to_dict(uri)
    delete!.(Ref(els), [:uri, :fragment])
    uri2 = HTTP.URI(; els...)
    is_file_uri = startswith(uri2.scheme, "file") || isempty(uri2.scheme)
    if is_file_uri && !isabspath(uri2.path)
        # Normalize a file path to an absolute path so creating a key is consistent.
        uri2 = HTTP.URIs.merge(uri2; path = abspath(joinpath(parent_dir, uri2.path)))
    end
    if !haskey(id_map, string(uri2))
        # id_map doesn't have this key so, fetch the ref and add it to id_map.
        id_map[string(uri2)] = if startswith(uri2.scheme, "http")
            @info("fetching remote ref $(uri2)")
            get_remote_schema(uri2).data
        else
            @assert is_file_uri
            @info("loading local ref $(uri2)")
            Schema(JSON.parsefile(uri2.path); parent_dir = dirname(uri2.path)).data
        end
    end

    p = JSONPointer.Pointer(uri.fragment; shift_index = true)
    return id_map[string(uri2)][p]
end

# Recursively find all "$ref" fields and resolve their path.

resolve_refs!(::Any, ::HTTP.URI, ::AbstractDict, ::String) = nothing

function resolve_refs!(
    schema::Vector,
    uri::HTTP.URI,
    id_map::AbstractDict,
    parent_dir::String
)
    for s in schema
        resolve_refs!(s, uri, id_map, parent_dir)
    end
    return
end

function resolve_refs!(
    schema::AbstractDict,
    uri::HTTP.URI,
    id_map::AbstractDict,
    parent_dir::String
)
    if haskey(schema, "id") && schema["id"] isa String
        # This block is for draft 4.
        uri = update_id(uri, schema["id"])
    end
    if haskey(schema, "\$id") && schema["\$id"] isa String
        # This block is for draft 6+.
        uri = update_id(uri, schema["\$id"])
    end
    for (k, v) in schema
        if k == "\$ref" && v isa String
            # This ref has not been resolved yet (otherwise it would not be a String).
            # We will replace the path string with the schema element pointed at, thus
            # marking it as resolved. This should prevent infinite recursions caused by
            # self referencing.
            schema["\$ref"] = find_ref(uri, id_map, v, parent_dir)
        else
            resolve_refs!(v, uri, id_map, parent_dir)
        end
    end
    return
end

function build_id_map(schema::AbstractDict)
    id_map = Dict{String, Any}("" => schema)
    build_id_map!(id_map, schema, HTTP.URI())
    return id_map
end

build_id_map!(::AbstractDict, ::Any, ::HTTP.URI) = nothing

function build_id_map!(id_map::AbstractDict, schema::Vector, uri::HTTP.URI)
    build_id_map!.(Ref(id_map), schema, Ref(uri))
    return
end

function build_id_map!(id_map::AbstractDict, schema::AbstractDict, uri::HTTP.URI)
    if haskey(schema, "id") && schema["id"] isa String
        # This block is for draft 4.
        uri = update_id(uri, schema["id"])
        id_map[string(uri)] = schema
    end
    if haskey(schema, "\$id") && schema["\$id"] isa String
        # This block is for draft 6+.
        uri = update_id(uri, schema["\$id"])
        id_map[string(uri)] = schema
    end
    for value in values(schema)
        build_id_map!(id_map, value, uri)
    end
    return
end

"""

    Schema(schema::AbstractDict; parent_dir::String = abspath("."))

Create a schema but with `schema` being a parsed JSON created with `JSON.parse()` or
`JSON.parsefile()`.

`parent_dir` is the path with respect to which references to local schemas are resolved.

## Examples

    my_schema = Schema(JSON.parsefile(filename))
    my_schema = Schema(JSON.parsefile(filename); parent_dir = "~/schemas")
"""
struct Schema
    data::Union{AbstractDict, Bool}

    Schema(schema::Bool; kwargs...) = new(schema)

    function Schema(
        schema::AbstractDict;
        parent_dir::String = abspath("."),
        parentFileDirectory = nothing,
    )
        if parentFileDirectory !== nothing
            @warn("kwarg `parentFileDirectory` is deprecated. Use `parent_dir` instead.")
            parent_dir = parentFileDirectory
        end
        schema = deepcopy(schema)  # Ensure we don't modify the user's data!
        id_map = build_id_map(schema)
        resolve_refs!(schema, HTTP.URI(), id_map, parent_dir)
        return new(schema)
    end
end

"""
    Schema(schema::String; parent_dir::String = abspath("."))

Create a schema for document validation by parsing the string `schema`.

`parent_dir` is the path with respect to which references to local schemas are resolved.

## Examples

    my_schema = Schema(\"\"\"{
        \"properties\": {
            \"foo\": {},
            \"bar\": {}
        },
        \"required\": [\"foo\"]
    }\"\"\")

    # Assume there exists `~/schemas/local_file.json`:
    my_schema = Schema(
        \"\"\"{
            "\$ref": "local_file.json"
        }\"\"\",
        parent_dir = "~/schemas"
    )
"""
Schema(schema::String; kwargs...) = Schema(JSON.parse(schema); kwargs...)

Base.show(io::IO, ::Schema) = print(io, "A JSONSchema")
