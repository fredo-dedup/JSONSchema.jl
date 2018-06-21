####################################################################
#  JSON schema parsing
####################################################################

using JSON

@compat abstract type SpecDef end


asserts_kw = ["type", "enum", "const",
              "multipleOf", "maximum", "exclusiveMaximum", "minimum", "exclusiveMinimum",
              "maxLength", "minLength", "pattern",
              "items", "additionalItems", "maxItems", "minItems", "uniqueItems", "contains",
              "maxProperties", "minProperties", "required", "properties",
              "patternProperties", "additionalProperties", "dependencies",
              "propertyNames",
              "allOf", "anyOf", "oneOf", "not"]
#
# 6.6. Keywords for Applying Subschemas Conditionally
# 6.6.1. if
# 6.6.2. then
# 6.6.3. else
# 6.7. Keywords for Applying Subschemas With Boolean Logic
# 6.7.1. allOf
# 6.7.2. anyOf
# 6.7.3. oneOf
# 6.7.4. not


struct Schema
  asserts::Dict{String, Any}
  annots::Dict{String, Any}
end

eachpropisaSchema(x::Dict) = map(p -> p[1] => Schema(p[2]), x)

Schema(x) = x
Schema(a::Array) = map(Schema,a)
function Schema(spec::Dict)
  assd = Dict{String, Any}()
  annd = Dict{String, Any}()
  for (k,v) in spec
    if k in asserts_kw
      if k in ["items", "additionalItems", "contains", "additionalProperties",
               "propertyNames", "not", "allOf", "anyOf", "oneOf"]
        assd[k] = Schema(v)
      elseif k in ["properties", "patternProperties"]
        assd[k] = eachpropisaSchema(v)
      elseif k == "dependencies"
        assd[k] = map(p -> p[1] => (p[2] isa Dict) ? Schema(p[2]) : p[2], v)
      else
        assd[k] = v
      end

    else
      annd[k] = v
    end
  end
  Schema(assd, annd)
end



function check(x, s::Schema)
  evaluate(x,s) == nothing
end

function evaluatefortype(x, typ::String)
  if typ == "string"
    x isa String || return "is not a string"
  elseif typ == "number"
    (x isa Int) || (x isa Float64) || return "is not a number"
  elseif typ == "integer"
    x isa Int || return "is not an integer"
  elseif typ == "array"
    x isa Array || return "is not an array"
  elseif typ == "boolean"
    x isa Bool || return "is not a boolean"
  elseif typ == "object"
    x isa Dict || return "is not an object"
  elseif typ == "null"
    (x == nothing) || return "is not null"
  end
  nothing
end

function evaluate(x, s::Schema, s0=s)
  # resolve refs and add to list of assertions
  asserts = copy(s.asserts)
  if haskey(s.annots, "\$ref")
    rpath = s.annots["\$ref"]
    if rpath[1] == '#'

  if haskey(asserts, "type")
    typ = asserts["type"]
    if typ isa Array
      any( evaluatefortype(x, typ2)==nothing for typ2 in typ ) ||
        return "is not any of the allowed types $typ"
    else
      ret = evaluatefortype(x, typ)
      (ret==nothing) || return ret
    end
  end

  if haskey(asserts, "enum")
    en = asserts["enum"]
    any( x == e for e in en) || return "expected to be one of $en"
  end

  if isa(x, Array)
    if haskey(asserts, "items")
      it = asserts["items"]
      if it isa Schema
        any( !check(el, it) for el in x ) && return "not an array of $it"
      elseif it isa Array
        for (i, iti) in enumerate(it)
          i > length(x) && break
          check(x[i], iti) || return "not a $iti at pos $i"
        end
        if haskey(asserts, "additionalItems") && (length(it) < length(x))
          addit = asserts["additionalItems"]
          if addit isa Bool
            (addit == false) && return "additional items not allowed"
          else
            for i in length(it)+1:length(x)
              check(x[i], addit) || return "not a $addit at pos $i"
            end
          end
        end
      end
    end

    if haskey(asserts, "maxItems")
      val = asserts["maxItems"]
      (length(x) <= val) || return "array longer than $val"
    end

    if haskey(asserts, "minItems")
      val = asserts["minItems"]
      (length(x) >= val) || return "array shorter than $val"
    end

    if haskey(asserts, "uniqueItems")
      uni = asserts["uniqueItems"]
      if uni
        (length(unique(x)) > 1) || return "non unique elements"
        #FIXME avoid the collapse of 1 / true into 1
      end
    end

    if haskey(asserts, "contains")
      sch = asserts["contains"]
      any(check(el, sch) for el in x) || return "does not contain $sch"
    end
  end

  if isa(x, Dict)

    if haskey(asserts, "dependencies")
      dep = asserts["dependencies"]
      for (k,v) in dep
        if haskey(x, k)
          if v isa Schema
            check(x,v) || return "is not a $v (dependency $k)"
          else
            for rk in v
              haskey(x, rk) || return "required property '$rk' missing (dependency $k)"
            end
          end
        end
      end
    end

    if haskey(asserts, "maxProperties")
      nb = asserts["maxProperties"]
      (length(x) <= nb) || return "nb of properties > $nb"
    end

    if haskey(asserts, "minProperties")
      nb = asserts["minProperties"]
      (length(x) >= nb) || return "nb of properties < $nb"
    end

    remainingprops = collect(keys(x))
    if haskey(asserts, "required")
      req = asserts["required"]
      for k in req
        (k in remainingprops) || return "required property '$k' missing"
      end
    end

    matchedprops = String[]
    if haskey(asserts, "patternProperties") && length(remainingprops) > 0
      patprop = asserts["patternProperties"]
      for k in remainingprops
        hasmatch = false
        for (rk, rtest) in patprop
          if ismatch(Regex(rk), k)
            hasmatch = true
            check(x[k], rtest) || return "property $k matches pattern $rk but is not a $rtest"
          end
        end
        hasmatch && push!(matchedprops, k)
      end
    end

    if haskey(asserts, "properties")
      prop = asserts["properties"]
      for k in intersect(remainingprops, keys(prop))
        check(x[k], prop[k]) || return "property $k is not a $(prop[k])"
        push!(matchedprops, k)
      end
    end

    remainingprops = setdiff(remainingprops, matchedprops)
    if haskey(asserts, "additionalProperties") && length(remainingprops) > 0
      addprop = asserts["additionalProperties"]
      if addprop isa Bool
        (addprop == false) && return "additional properties not allowed"
      else
        for k in remainingprops
          check(x[k], addprop) || return "additional property $k is not a $addprop"
        end
      end
    end
  end

  if (x isa Int) || (x isa Float64)
    if haskey(asserts, "multipleOf")
      val = asserts["multipleOf"]
      δ = abs(x - val*round(x / val))
      (δ < eps(Float64)) || return "not a multipleOf of $val"
    end

    if haskey(asserts, "maximum")
      val = asserts["maximum"]
      (x <= val) || return "not <= $val"
    end

    if haskey(asserts, "exclusiveMaximum")
      val = asserts["exclusiveMaximum"]
      if (val isa Bool) && haskey(asserts, "maximum")  # draft 4
        val2 = asserts["maximum"]
        if val
          (x < val2) || return "not < $val2"
        else
          (x <= val2) || return "not <= $val2"
        end
      elseif val isa Number
        (x < val) || return "not < $val"
      end
    end

    if haskey(asserts, "minimum")
      val = asserts["minimum"]
      (x >= val) || return "not >= $val"
    end

    if haskey(asserts, "exclusiveMinimum")
      val = asserts["exclusiveMinimum"]
      if (val isa Bool) && haskey(asserts, "minimum")  # draft 4
        val2 = asserts["minimum"]
        if val
          (x > val2) || return "not > $val2"
        else
          (x >= val2) || return "not >= $val2"
        end
      elseif val isa Number
        (x > val) || return "not > $val"
      end
    end
  end

  if x isa String
    if haskey(asserts, "maxLength")
      val = asserts["maxLength"]
      (length(x) > val) && return "longer than $val characters"
    end

    if haskey(asserts, "minLength")
      val = asserts["minLength"]
      (length(x) < val) && return "shorter than $val characters"
    end

    if haskey(asserts, "pattern")
      pat = asserts["pattern"]
      ismatch(Regex(pat), x) || return "does not match pattern $pat"
    end
  end


  if haskey(asserts, "allOf")
    schs = asserts["allOf"]
    all( check(x, subsch) for subsch in schs) || return "does not satisfy all of $schs"
  end

  if haskey(asserts, "anyOf")
    schs = asserts["anyOf"]
    any( check(x, subsch) for subsch in schs) || return "does not satisfy any of $schs"
  end

  if haskey(asserts, "oneOf")
    schs = asserts["oneOf"]
    check(x, schs[1])
    check(x, schs[1])
    (sum(check(x, subsch) for subsch in schs)==1) || return "does not satisfy one of $schs"
  end

  if haskey(asserts, "not")
    notassert = asserts["not"]
    check(x, notassert) && return "satisfies 'not' assertion $notassert"
  end

  nothing
end





#
#
# # struct for definitions without a type given
# struct NoTypeDef <: SpecDef
#   elements::Dict{String, Any}
# end
#
# type ObjDef <: SpecDef
#   desc::String
#   props::Dict{String, SpecDef}
#   addprops::SpecDef
#   required::Set{String}
# end
#
# type NumberDef <: SpecDef
#   desc::String
#   multipleOf::Number
#   maximum::Number
#   exclusive::Maximum
# end
# NumberDef(spec::Dict) = NumberDef(get(spec, "description", ""))
#
# type IntDef <: SpecDef
#   desc::String
# end
# IntDef(spec::Dict)    = IntDef(get(spec, "description", ""))
#
# type StringDef <: SpecDef
#   desc::String
#   enum::Set{String}
# end
# StringDef(spec::Dict) =
#   StringDef(get(spec, "description", ""),
#             Set{String}(get(spec, "enum", String[])))
#
# type BoolDef <: SpecDef
#   desc::String
# end
# BoolDef(spec::Dict)   = BoolDef(get(spec, "description", ""))
#
# type ArrayDef <: SpecDef
#   desc::String
#   items::SpecDef
# end
# ArrayDef(spec::Dict) =
#   ArrayDef(get(spec, "description", ""), toDef(spec["items"]))
#
# type UnionDef <: SpecDef
#   desc::String
#   items::Vector
# end
#
# type VoidDef <: SpecDef
#   desc::String
# end
#
# type AnyDef <: SpecDef
#   desc::String
# end
#
#
# function elemtype(typ::String)
#   typ=="number"  && return NumberDef("")
#   typ=="boolean" && return BoolDef("")
#   typ=="integer" && return IntDef("")
#   typ=="string"  && return StringDef("", Set{String}())
#   typ=="null"    && return VoidDef("")
#   error("unknown elementary type $typ")
# end
#
#
# ###########  Schema parsing  ##############
#
# function toDef(spec::Dict)
#   if haskey(spec, "type")
#     typ = spec["type"]
#
#     if isa(typ, Vector)  # parse as UnionDef
#       if length(spec["type"]) > 1
#         return UnionDef(get(spec, "description", ""), elemtype.(spec["type"]))
#       end
#       typ = spec["type"][1]
#     end
#
#     if isa(typ, String)
#       typ=="null"    && return VoidDef("")
#       typ=="number"  && return NumberDef(spec)
#       typ=="boolean" && return BoolDef(spec)
#       typ=="integer" && return IntDef(spec)
#       typ=="string"  && return StringDef(spec)
#       typ=="array"   && return ArrayDef(spec)
#
#       if typ == "object"
#         ret = ObjDef(get(spec, "description", ""),
#                      Dict{String, SpecDef}(),
#                      VoidDef(""),
#                      Set{String}(get(spec, "required", String[])))
#
#         if haskey(spec, "properties")
#           for (k,v) in spec["properties"]
#             ret.props[k] = toDef(v)
#           end
#         end
#
#         if haskey(spec, "required")
#           ret.required = Set(spec["required"])
#         end
#
#         if haskey(spec, "additionalProperties") && isa(spec["additionalProperties"], Dict)
#           ret.addprops = toDef(spec["additionalProperties"])
#         end
#
#         return ret
#       end
#
#       error("unknown type $typ")
#     end
#
#     error("type $typ is neither an array nor a string")
#
#   elseif haskey(spec, "\$ref")
#     rname = split(spec["\$ref"], "/")[3] # name of definition
#     # if this ref has already been seen (it is in the 'refs' dict) fetch its
#     # SpecDef. Otherwise create.
#     if !haskey(refs, rname)
#       # Some refs are auto-referential. We need to create a dummy def to avoid
#       # infinite recursion.
#       refs[rname] = VoidDef("")
#       refs[rname] = toDef(schema["definitions"][rname])
#       # reparse a second time to set correctly auto-referential children props
#       temp = toDef(schema["definitions"][rname])
#       # and update refs[rname]
#       for field in fieldnames(refs[rname])
#         setfield!(refs[rname], field, getfield(temp, field))
#       end
#     end
#     return refs[rname]
#
#   elseif haskey(spec, "anyOf")
#     return UnionDef(get(spec, "description", ""),
#                     toDef.(spec["anyOf"]))
#
#   elseif length(spec) == 0
#     return AnyDef("")
#
#   else
#     nd  = map(spec) do p
#       v = isa(p[2], Dict) ? toDef(p[2]) : p[2]
#       p[1] => v
#     end
#     return NoTypeDef(nd)
#   end
# end
#
#
# sp = Dict("abcd" => 456, "xyz" => 1)
#
# map(p -> p[1] => p[2] * 2, sp)
