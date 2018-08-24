####################################################################
#  JSON schema definition and parsing
####################################################################

import Base: setindex!, getindex, haskey, show

## transforms escaped characters in JPaths back to their original value
function unescapeJPath(raw::String)
  ret = replace(raw, "~0" => "~")
  ret = replace(ret, "~1" => "/")

  m = match(r"%([0-9A-F]{2})", ret)
  if m != nothing
    repls = Dict()
    for c in m.captures
      # c = first(m.captures)
      haskey(repls, String("%$c")) && continue
      repls[String("%$c")] = "$(Char(Meta.parse("0x" * c)))"
    end

    for (k,v) in repls
      ret = replace(ret, k => v)
    end
  end

  ret
end

## decomposes an URI into its elements
function todict(uri::HTTP.URI)
  pdict = Dict( fn => getfield(uri, fn) for fn in fieldnames(HTTP.URI))
  delete!(pdict, :uri)
end

## removes the fragment part of an URI
function rmfragment(uri::HTTP.URI)
  els = todict(uri)
  delete!(els, :fragment)
  HTTP.URI(;els...)
end

## calculates the full id of the explored item using the parent URI in
#   'id0', and the 'id' property in 's'
function updateid(id0::HTTP.URI, s::String)
  id2 = HTTP.URI(s)
  id2.scheme != "" && return id2

  els = todict(id0)
  if id2.path != ""  # replace path of id0
    oldpath = match(r"^(.*/).*$", id0.path)
    if oldpath == nothing
      els[:path] = "/" * id2.path
    else
      els[:path] = oldpath.captures[1] * id2.path
    end
  end

  els[:fragment] = id2.fragment

  HTTP.URI(;els...)
end

## constructs the map of ids to schema elements
mkidmap!(map, x, id0::HTTP.URI) = nothing
mkidmap!(map, v::Vector, id0::HTTP.URI) = foreach(e -> mkidmap!(map,e,id0), v)
function mkidmap!(map::Dict, el::Dict, id0::HTTP.URI)
  if haskey(el, "id") && isa(el["id"], String) # draft 04
    id0 = updateid(id0, el["id"])
    map[string(id0)] = el
  elseif haskey(el, "\$id") && isa(el["\$id"], String) # draft 06+
    id0 = updateid(id0, el["\$id"])
    map[string(id0)] = el
  end

  for (k,v) in el
    mkidmap!(map, v, id0)
  end
end

## searches the element refered to by JSPointer/fragment in path in the schema s
function findelement(s, path)
  for el in split(path, "/")
    realel = unescapeJPath(String(el))
    (realel == "") && continue
    if s isa Dict
      haskey(s, realel) || error("missing property '$realel' in $s")
      s = s[realel]
    elseif s isa Vector
      idx = Meta.parse(realel)
      (idx isa Int) || error("expected numeric array index instead of '$realel'")
      idx += 1
      (length(s) < idx) && error("item index $(idx-1) larger than array $s")
      s = s[idx]
    else
      error("unmanaged type in ref resolution $(typeof(s)) - $s")
    end
  end
  s
end

## fetch remote schema
function getremoteschema(uri::HTTP.URI)
  r = HTTP.request("GET", uri)
  (r.status != 200) && error("remote ref $uri not found")
  Schema(JSON.parse(String(r.body))) # process remote ref
end

function findref(id0, idmap, path::String)
  # path refers to root
  (path in ["", "#"]) && return idmap[string(id0)]

  # path is a JPointer
  (length(path) > 1 ) && (path[1:2] == "#/") &&
    return findelement(idmap[string(id0)], path[3:end])

  # path is a URI
  uri = updateid(id0, path) # fullRefURI(HTTP.URI(path), id0)
  uri2 = rmfragment(uri) # without JPointer

  if !haskey(idmap, string(uri2))  # if not referenced already, fetch remote ref, add to idmap
    @info("fetching $uri2")
    idmap[string(uri2)] = getremoteschema(uri2).data
  end

  findelement(idmap[string(uri2)], uri.fragment)
end

# finds recursively all "$ref" and resolve their path
resolverefs!(s, id0, idmap) = nothing
resolverefs!(s::Vector, id0, idmap) = foreach(e -> resolverefs!(e, id0, idmap), s)
function resolverefs!(s::Dict, id0, idmap)
  if haskey(s, "id") && isa(s["id"], String) # draft 04
    id0 = updateid(id0, s["id"])
  elseif haskey(s, "\$id") && isa(s["\$id"], String) # draft 06+
    id0 = updateid(id0, s["\$id"])
  end

  for (k,v) in s
    if (k == "\$ref") && (v isa String)
      # This ref has not been resolved yet (otherwise it would not be a String)
      # We will replace the path string with the schema element pointed at, thus marking it as
      # resolved. This should prevent infinite recursions caused by self referencing
      s["\$ref"] = findref(id0, idmap, v)
    else
      resolverefs!(v, id0, idmap)
    end
  end
end



################################################################################
#  Schema struct definition
################################################################################

"""
`Schema(sch::String)`

Create a schema for document validation. `sch` should be a String containing a
valid JSON.

`Schema(sch::Dict)`

Create a schema but with `sch` being a parsed JSON created with `JSON.parse()` or
`JSON.parsefile()`.

## Example

```julia
julia> myschema = Schema("
  {
    \"properties\": {
      \"foo\": {},
      \"bar\": {}
    },
    \"required\": [\"foo\"]
  }
  ")

julia> sch = JSON.parsefile(filepath)
julia> myschema = Schema(sch)
```
"""
struct Schema
  data::Union{Dict{String, Any}, Bool}

  function Schema(spec0::Bool; idmap0=Dict{String, Any}())
    new(spec0)
  end

  function Schema(sp::String; idmap0=Dict{String, Any}())
    Schema(JSON.parse(sp), idmap0=idmap0)
  end

  function Schema(spec0::Dict; idmap0=Dict{String, Any}())
    spec  = deepcopy(spec0)
    idmap = deepcopy(idmap0)

    # construct dictionary of 'id' properties to resolve references later
    id0 = HTTP.URI()
    idmap[string(id0)] = spec
    mkidmap!(idmap, spec, id0)

    # resolve all refs to the corresponding schema elements
    resolverefs!(spec, id0, idmap)

    new(spec)
  end
end


setindex!(x::Schema, val, key) = setindex!(x.data, val, key)
getindex(x::Schema, key) = getindex(x.data, key)
haskey(x::Schema, key) = haskey(x.data, key)

function show(io::IO, sch::Schema)
  show(io, Schema)
end
