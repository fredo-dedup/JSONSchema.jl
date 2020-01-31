# Transform escaped characters in JPaths back to their original value.
function unescape_jpath(raw::String)
    ret = replace(replace(raw, "~0" => "~"), "~1" => "/")
    m = match(r"%([0-9A-F]{2})", ret)
    if m !== nothing
        for c in m.captures
            ret = replace(ret, "%$(c)" => Char(parse(UInt8, "0x$(c)")))
        end
    end
    return ret
end

function uri_to_dict(uri::HTTP.URI; remove_fields = Symbol[:uri])
    dict = Dict(name => getfield(uri, name) for name in fieldnames(HTTP.URI))
    delete!.(Ref(dict), remove_fields)
    return dict
end

# Calculate the full id of the explored item using the parent URI in
# 'id0', and the 'id' property in 's'
function update_id(id0::HTTP.URI, s::String)
    id2 = HTTP.URI(s)
    if !isempty(id2.scheme)
        return id2
    end
    els = uri_to_dict(id0)
    els[:fragment] = id2.fragment
    if !isempty(id2.path) # replace path of id0
        oldpath = match(r"^(.*/).*$", id0.path)
        els[:path] = oldpath == nothing ? id2.path : oldpath.captures[1] * id2.path
    end
    return HTTP.URI(; els...)
end

# Search the element refered to by JSPointer/fragment in `path` in the `schema`.
function get_element(schema, path::AbstractString)
    for element in split(path, "/"; keepempty = false)
        s_element = unescape_jpath(String(element))
        schema = _recurse_get_element(schema, s_element)
    end
    return schema
end

function _recurse_get_element(schema::Any, ::String)
    error("unmanaged type in ref resolution $(typeof(schema)): $(schema).")
end

function _recurse_get_element(schema::Dict, element::String)
    if !haskey(schema, element)
        error("missing property '$(element)' in $(schema).")
    end
    return schema[element]
end

function _recurse_get_element(schema::Vector, element::String)
    index = tryparse(Int, element)  # Remember that `index` is 0-indexed!
    if index === nothing
        error("expected integer array index instead of '$(element)'.")
    elseif index >= length(schema)
        error("item index $(index) is larger than array $(schema).")
    end
    return schema[index + 1]
end

function get_remote_schema(uri::HTTP.URI)
    r = HTTP.get(uri)
    if r.status != 200
        error("Unable to get remote schema at $uri. HTTP status = $(r.status)")
    end
    return Schema(JSON.parse(String(r.body)))
end

function find_ref(id0, idmap, path::String, parentFileDirectory::String)
    if path == "" || path == "#"  # This path refers to the root schema.
        return idmap[string(id0)]
    elseif startswith(path, "#/")  # This path is a JPointer.
        return get_element(idmap[string(id0)], path[3:end])
    end
    # If we reach here, the path is a URI.
    uri = update_id(id0, path)
    # Strip fragment from uri.
    uri2 = HTTP.URI(; uri_to_dict(uri; remove_fields = [:uri, :fragment])...)
    isFileUri = startswith(uri2.scheme, "file") || isempty(uri2.scheme)
    # normalize a file path to an absolute path so creating a key is consistent
    if isFileUri && !isabspath(uri2.path)
        uri2 = HTTP.URIs.merge(
            uri2;
            path = abspath(joinpath(parentFileDirectory, uri2.path))
        )
    end
    if !haskey(idmap, string(uri2))  # if not referenced already, fetch remote ref, add to idmap
        if startswith(uri2.scheme, "http")
            @info("fetching remote ref $(uri2)")
            idmap[string(uri2)] = get_remote_schema(uri2).data
        elseif isFileUri
            @info("loading local ref $(uri2)")
            idmap[string(uri2)] = Schema(
                JSON.parsefile(uri2.path);
                parentFileDirectory = dirname(uri2.path)
            ).data
        end
    end
    return get_element(idmap[string(uri2)], uri.fragment)
end

# Recursively find all "$ref" fields and resolve their path.
resolve_refs!(::Any, ::HTTP.URI, ::Dict{String,Any}, ::String) = nothing

function resolve_refs!(
    schema::Vector,
    uri::HTTP.URI,
    id_map::Dict{String,Any},
    parentFileDirectory::String
)
    for s in schema
        resolve_refs!(s, uri, id_map, parentFileDirectory)
    end
    return
end

function resolve_refs!(
    schema::Dict,
    uri::HTTP.URI,
    id_map::Dict{String,Any},
    parentFileDirectory::String
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
            schema["\$ref"] = find_ref(uri, id_map, v, parentFileDirectory)
        else
            resolve_refs!(v, uri, id_map, parentFileDirectory)
        end
    end
    return
end

# Construct the map of ids to schema elements.
function build_id_map(schema::Dict)
    id_map = Dict{String, Any}("" => schema)
    build_id_map!(id_map, schema, HTTP.URI())
    return id_map
end

build_id_map!(::Dict{String,Any}, ::Any, ::HTTP.URI) = nothing

function build_id_map!(id_map::Dict{String,Any}, schema::Vector, uri::HTTP.URI)
    build_id_map!.(Ref(id_map), schema, Ref(uri))
    return
end

function build_id_map!(id_map::Dict{String,Any}, schema::Dict, uri::HTTP.URI)
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
    Schema(schema::String)

Create a schema for document validation. `schema` should be a String containing a
valid JSON.

## Example

    my_schema = Schema(\"\"\"{
        \"properties\": {
            \"foo\": {},
            \"bar\": {}
        },
        \"required\": [\"foo\"]
    }\"\"\")

    Schema(schema::Dict)

Create a schema but with `schema` being a parsed JSON created with `JSON.parse()` or
`JSON.parsefile()`.

## Example

    julia> my_schema = Schema(JSON.parsefile(filename))
"""
struct Schema
    data::Union{Dict{String, Any}, Bool}

    Schema(schema::Bool; kwargs...) = new(schema)

    function Schema(
        schema::Dict;
        parentFileDirectory::String = abspath("."),
    )
        schema = deepcopy(schema)  # Ensure we don't modify the user's data!
        id_map = build_id_map(schema)
        resolve_refs!(schema, HTTP.URI(), id_map, parentFileDirectory)
        return new(schema)
    end
end

Schema(schema::String; kwargs...) = Schema(JSON.parse(schema); kwargs...)

Base.show(io::IO, ::Schema) = print(io, "A JSONSchema")
