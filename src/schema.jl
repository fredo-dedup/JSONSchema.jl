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
      ret = replace(ret, k, v)
    end
  end

  ret
end

## tranforms uri, if relative, to an absolute URI using the context URI in id0
function toabsoluteURI(uri::HTTP.URI, id0::HTTP.URI)
  # @info "(1) uri : $uri, id0 : $id0"
  if uri.scheme == ""  # uri is relative to base uri => change just the path of id0
    uri = HTTP.URI(scheme   = id0.scheme,
                   userinfo = id0.userinfo,
                   host     = id0.host,
                   port     = id0.port,
                   query    = id0.query,
                   path     = "/" * strip(uri.path, '/'))
  else
    uri = HTTP.URI(scheme   = uri.scheme,
             userinfo = uri.userinfo,
             host     = uri.host,
             port     = uri.port,
             query    = uri.query,
             path     = "")
  end
  # @info "(->1) uri : $uri"
  uri
end

function toabsoluteURI2(uri::HTTP.URI, id0::HTTP.URI)
  # @info "(2) uri : $uri, id0 : $id0"
  if uri.scheme == ""  # uri is relative to base uri => change just the path of id0
    newpath = ( id0.path == "" ? "" : "/" * strip(id0.path, '/') ) *
      "/" * strip(uri.path, '/')

    uri = HTTP.URI(scheme   = id0.scheme,
                   userinfo = id0.userinfo,
                   host     = id0.host,
                   port     = id0.port,
                   query    = id0.query,
                   path     = newpath)
  else
    uri = HTTP.URI(scheme   = uri.scheme,
             userinfo = uri.userinfo,
             host     = uri.host,
             port     = uri.port,
             query    = uri.query,
             path     = uri.path)
  end
  # @info "(->2) uri : $uri"
  uri
end

## creates a new URI from `uri` with the provided fragment
function setfragment(uri::HTTP.URI, fragment::String)
  HTTP.URI(scheme   = uri.scheme,
           userinfo = uri.userinfo,
           host     = uri.host,
           port     = uri.port,
           path     = uri.path,
           query    = uri.query,
           fragment = fragment)
end

## removes the fragment part of an URI
function rmfragment(uri::HTTP.URI)
  HTTP.URI(scheme   = uri.scheme,
           userinfo = uri.userinfo,
           host     = uri.host,
           port     = uri.port,
           path     = uri.path,
           query    = uri.query)
end

## constructs the map of ids to schema elements
mkidmap!(map, x, id0::HTTP.URI) = nothing
mkidmap!(map, v::Vector, id0::HTTP.URI) = foreach(e -> mkidmap!(map,e,id0), v)
function mkidmap!(map::Dict, el::Dict, id0::HTTP.URI)
  if haskey(el, "id")
    v = el["id"]
    if v[1] == '#'  # plain name fragment
      uri = setfragment(id0, v[2:end])
    else
      uri = toabsoluteURI(HTTP.URI(v), id0)
      id0 = uri # update base uri for inner properties
    end
    map[string(uri)] = el
  end

  for (k,v) in el
    mkidmap!(map, v, id0)
  end
end

## searches the element refered to by JSPointer in path in the schema s
function _findelt(s, path)
  for el in split(path, "/")
    realel = unescapeJPath(String(el))
    (realel == "") && continue
    if s isa Dict
      haskey(s, realel) || error("missing property '$realel' in $s")
      s = s[realel]
    elseif s isa Vector
      idx = parse(realel)
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

function findref(id0, idmap, path::String)
  s0 = idmap[string(id0)]

  # path refers to root
  (length(path) == 0) && return s0
  (path == "#") && return s0

  # path is a JPointer
  (path[1:2] == "#/") && return _findelt(s0, path[3:end])

  # path is a URI
  uri = toabsoluteURI2(HTTP.URI(path), id0)

  #  uri stripped of JPointer (aka 'fragment')
  uri2 = rmfragment(uri) # without JPointer

  if ! haskey(idmap, string(uri2))  # if not referenced already, fetch remote ref, add to idmap
    @info("fetching $uri2")
    r = HTTP.request("GET", uri2)
    (r.status != 200) && error("remote ref $uri2 not found")
    rref = Schema(JSON.parse(String(r.body))) # process remote ref
    idmap[string(uri2)] = rref.data
  end

  _findelt(idmap[string(uri2)], uri.fragment)
end


# finds recursively all "$ref" and resolve their path
resolverefs!(s, id0, idmap) = nothing
resolverefs!(s::Vector, id0, idmap) = foreach(e -> resolverefs!(e, id0, idmap), s)
function resolverefs!(s::Dict, id0, idmap)
  ## update, if necessary, the base URI
  if haskey(s, "id")
    v = s["id"]
    if v[1] != '#' # not a plain name fragment
      uri = toabsoluteURI(HTTP.URI(v), id0)
      id0 = uri # update base uri for inner properties
    end
  end

  for (k,v) in s
    if (k == "\$ref") && (v isa String)
      # This ref has not been resolved yet (otherwise it would not be a String)
      # We will replace the path string with the schema element pointed at, thus marking it as
      # resolved. This should prevent infinite recursions caused by self referencing
      # path = s["\$ref"]
      #  println(join([id0, collect(keys(idmap)), v], " - "))
      s["\$ref"] = findref(id0, idmap, v)
    else
      resolverefs!(v, id0, idmap)
    end
  end
end



################################################################################
#  Schema struct definition
################################################################################

struct Schema
  data::Dict{String, Any}

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
