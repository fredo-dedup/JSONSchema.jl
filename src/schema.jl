####################################################################
#  JSON schema definition and parsing
####################################################################

asserts_kw = ["type", "enum", "const",
              "multipleOf", "maximum", "exclusiveMaximum", "minimum", "exclusiveMinimum",
              "maxLength", "minLength", "pattern",
              "items", "additionalItems", "maxItems", "minItems", "uniqueItems", "contains",
              "maxProperties", "minProperties", "required", "properties",
              "patternProperties", "additionalProperties", "dependencies",
              "propertyNames",
              "allOf", "anyOf", "oneOf", "not"]

# 6.6. Keywords for Applying Subschemas Conditionally
# 6.6.1. if
# 6.6.2. then
# 6.6.3. else


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
      assd[k] = Schema(v)
    end
  end
  Schema(assd, annd)
end
