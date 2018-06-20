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
              "propertyNames"]

              6.6. Keywords for Applying Subschemas Conditionally
              6.6.1. if
              6.6.2. then
              6.6.3. else
              6.7. Keywords for Applying Subschemas With Boolean Logic
              6.7.1. allOf
              6.7.2. anyOf
              6.7.3. oneOf
              6.7.4. not


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
               "propertyNames"]
        assd[k] = Schema(v)
      elseif k in ["properties", "patternProperties"]
        assd[k] = eachpropisaSchema(v)
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

function evaluate(x, s::Schema)
  if haskey(s.asserts, "type")
    typ = s.asserts["type"]
    if typ == "string"
      x isa String || return "is not a string"
    elseif typ == "number"
      x isa Number || return "is not a number"
    elseif typ == "array"
      x isa Array || return "is not an array"
    elseif typ == "boolean"
      x isa Bool || return "is not a boolean"
    elseif typ == "object"
      x isa Dict || return "is not an object"
    elseif typ == "null"
      x == nothing || return "is not null"
    end
  end

  if haskey(s.asserts, "enum")
    en = s.asserts["enum"]
    any( x == e for e in en) || return "expected to be one of $en"
  end
  nothing
end







# struct for definitions without a type given
struct NoTypeDef <: SpecDef
  elements::Dict{String, Any}
end

type ObjDef <: SpecDef
  desc::String
  props::Dict{String, SpecDef}
  addprops::SpecDef
  required::Set{String}
end

type NumberDef <: SpecDef
  desc::String
  multipleOf::Number
  maximum::Number
  exclusive::Maximum
end
NumberDef(spec::Dict) = NumberDef(get(spec, "description", ""))

type IntDef <: SpecDef
  desc::String
end
IntDef(spec::Dict)    = IntDef(get(spec, "description", ""))

type StringDef <: SpecDef
  desc::String
  enum::Set{String}
end
StringDef(spec::Dict) =
  StringDef(get(spec, "description", ""),
            Set{String}(get(spec, "enum", String[])))

type BoolDef <: SpecDef
  desc::String
end
BoolDef(spec::Dict)   = BoolDef(get(spec, "description", ""))

type ArrayDef <: SpecDef
  desc::String
  items::SpecDef
end
ArrayDef(spec::Dict) =
  ArrayDef(get(spec, "description", ""), toDef(spec["items"]))

type UnionDef <: SpecDef
  desc::String
  items::Vector
end

type VoidDef <: SpecDef
  desc::String
end

type AnyDef <: SpecDef
  desc::String
end


function elemtype(typ::String)
  typ=="number"  && return NumberDef("")
  typ=="boolean" && return BoolDef("")
  typ=="integer" && return IntDef("")
  typ=="string"  && return StringDef("", Set{String}())
  typ=="null"    && return VoidDef("")
  error("unknown elementary type $typ")
end


###########  Schema parsing  ##############

function toDef(spec::Dict)
  if haskey(spec, "type")
    typ = spec["type"]

    if isa(typ, Vector)  # parse as UnionDef
      if length(spec["type"]) > 1
        return UnionDef(get(spec, "description", ""), elemtype.(spec["type"]))
      end
      typ = spec["type"][1]
    end

    if isa(typ, String)
      typ=="null"    && return VoidDef("")
      typ=="number"  && return NumberDef(spec)
      typ=="boolean" && return BoolDef(spec)
      typ=="integer" && return IntDef(spec)
      typ=="string"  && return StringDef(spec)
      typ=="array"   && return ArrayDef(spec)

      if typ == "object"
        ret = ObjDef(get(spec, "description", ""),
                     Dict{String, SpecDef}(),
                     VoidDef(""),
                     Set{String}(get(spec, "required", String[])))

        if haskey(spec, "properties")
          for (k,v) in spec["properties"]
            ret.props[k] = toDef(v)
          end
        end

        if haskey(spec, "required")
          ret.required = Set(spec["required"])
        end

        if haskey(spec, "additionalProperties") && isa(spec["additionalProperties"], Dict)
          ret.addprops = toDef(spec["additionalProperties"])
        end

        return ret
      end

      error("unknown type $typ")
    end

    error("type $typ is neither an array nor a string")

  elseif haskey(spec, "\$ref")
    rname = split(spec["\$ref"], "/")[3] # name of definition
    # if this ref has already been seen (it is in the 'refs' dict) fetch its
    # SpecDef. Otherwise create.
    if !haskey(refs, rname)
      # Some refs are auto-referential. We need to create a dummy def to avoid
      # infinite recursion.
      refs[rname] = VoidDef("")
      refs[rname] = toDef(schema["definitions"][rname])
      # reparse a second time to set correctly auto-referential children props
      temp = toDef(schema["definitions"][rname])
      # and update refs[rname]
      for field in fieldnames(refs[rname])
        setfield!(refs[rname], field, getfield(temp, field))
      end
    end
    return refs[rname]

  elseif haskey(spec, "anyOf")
    return UnionDef(get(spec, "description", ""),
                    toDef.(spec["anyOf"]))

  elseif length(spec) == 0
    return AnyDef("")

  else
    nd  = map(spec) do p
      v = isa(p[2], Dict) ? toDef(p[2]) : p[2]
      p[1] => v
    end
    return NoTypeDef(nd)
  end
end


sp = Dict("abcd" => 456, "xyz" => 1)

map(p -> p[1] => p[2] * 2, sp)
