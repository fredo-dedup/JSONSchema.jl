struct SingleIssue
    x
    path::String
    reason::String
    val
end

function Base.show(io::IO, issue::SingleIssue)
    println(io, """Validation failed:
    path:         $(isempty(issue.path) ? "top-level" : issue.path)
    instance:     $(issue.x)
    schema key:   $(issue.reason)
    schema value: $(issue.val)""")
end

"""
    validate(x, s::Schema)

Validate document `x` is valid against the Schema `s`. If valid, return `nothing`, else
return a `SingleIssue`. When printed, the returned `SingleIssue` describes the reason why
the validation failed.

## Examples

    julia> schema = Schema(
               Dict(
                   "properties" => Dict(
                       "foo" => Dict(),
                       "bar" => Dict()
                   ),
                   "required" => ["foo"]
               )
           )
    Schema

    julia> data_pass = Dict("foo" => true)
    Dict{String,Bool} with 1 entry:
      "foo" => true

    julia> data_fail = Dict("bar" => 12.5)
    Dict{String,Float64} with 1 entry:
      "bar" => 12.5

    julia> validate(data_pass, schema)

    julia> validate(data_fail, schema)
    Validation failed:
    path:         top-level
    instance:     Dict("bar"=>12.5)
    schema key:   required
    schema value: ["foo"]
"""
function validate(x, schema::Schema)
    return _validate(x, schema.data, "")
end

Base.isvalid(x, schema::Schema) = validate(x, schema) === nothing

function _validate(x, schema, path::String)
    schema = _resolve_refs(schema)
    return _validate_entry(x, schema, path)
end

function _validate_entry(x, schema::AbstractDict, path)
    for (k, v) in schema
        ret = _validate(x, schema, Val{Symbol(k)}(), v, path)
        if ret !== nothing
            return ret
        end
    end
    return
end

function _validate_entry(x, schema::Bool, path::String)
    return schema ? nothing : SingleIssue(x, path, "schema", schema)
end

function _resolve_refs(schema::AbstractDict, explored_refs = Any[schema])
    if !haskey(schema, "\$ref")
        return schema
    end
    schema = schema["\$ref"]
    if any(x -> x === schema, explored_refs)
        error("cannot support circular references in schema.")
    end
    push!(explored_refs, schema)
    return _resolve_refs(schema, explored_refs)
end
_resolve_refs(schema, explored_refs = Any[]) = schema

# Default fallback
_validate(::Any, ::Any, ::Val, ::Any, ::String) = nothing

###
### Core JSON Schema
###

# 9.2.1.1
function _validate(x, schema, ::Val{:allOf}, val::Vector, path::String)
    for v in val
        ret = _validate(x, v, path)
        if ret !== nothing
            return ret
        end
    end
    return
end

# 9.2.1.2
function _validate(x, schema, ::Val{:anyOf}, val::Vector, path::String)
    for v in val
        if _validate(x, v, path) === nothing
            return
        end
    end
    return SingleIssue(x, path, "anyOf", val)
end

# 9.2.1.3
function _validate(x, schema, ::Val{:oneOf}, val::Vector, path::String)
    found_match = false
    for v in val
        if _validate(x, v, path) === nothing
            if found_match # Found more than one match!
                return SingleIssue(x, path, "oneOf", val)
            end
            found_match = true
        end
    end
    return found_match ? nothing : SingleIssue(x, path, "oneOf", val)
end

# 9.2.1.4
function _validate(x, schema, ::Val{:not}, val, path::String)
    ret = _validate(x, val, path)
    return ret === nothing ? SingleIssue(x, path, "not", val) : nothing
end

# 9.2.2.1: if

# 9.2.2.2: then

# 9.2.2.3: else

###
### Checks for Arrays.
###

# 9.3.1.1
function _validate(x::Vector, schema, ::Val{:items}, val::AbstractDict, path::String)
    items = fill(false, length(x))
    for (i, xi) in enumerate(x)
        ret = _validate(xi, val, path * "[$(i)]")
        if ret !== nothing
            return ret
        end
        items[i] = true
    end
    additionalItems = get(schema, "additionalItems", nothing)
    return _additional_items(x, schema, items, additionalItems, path)
end

function _validate(x::Vector, schema, ::Val{:items}, val::Vector, path::String)
    items = fill(false, length(x))
    for (i, xi) in enumerate(x)
        if i > length(val)
            break
        end
        ret = _validate(xi, val[i], path * "[$(i)]")
        if ret !== nothing
            return ret
        end
        items[i] = true
    end
    additionalItems = get(schema, "additionalItems", nothing)
    return _additional_items(x, schema, items, additionalItems, path)
end

function _validate(x::Vector, schema, ::Val{:items}, val::Bool, path::String)
    return val || (!val && length(x) == 0) ? nothing : SingleIssue(x, path, "items", val)
end

function _additional_items(x, schema, items, val, path)
    for i = 1:length(x)
        if items[i]
            continue  # Validated against 'items'.
        end
        ret = _validate(x[i], val, path * "[$(i)]")
        if ret !== nothing
            return ret
        end
    end
    return
end

function _additional_items(x, schema, items, val::Bool, path)
    return !val && !all(items) ? SingleIssue(x, path, "additionalItems", val) : nothing
end

_additional_items(x, schema, items, val::Nothing, path) = nothing

# 9.3.1.2
function _validate(x::Vector, schema, ::Val{:additionalItems}, val, path::String)
    return  # Supported in `items`.
end

# 9.3.1.3: unevaluatedProperties

# 9.3.1.4
function _validate(x::Vector, schema, ::Val{:contains}, val, path::String)
    for (i, xi) in enumerate(x)
        ret = _validate(xi, val, path * "[$(i)]")
        if ret === nothing
            return
        end
    end
    return SingleIssue(x, path, "contains", val)
end

###
### Checks for Objects
###

# 9.3.2.1
function _validate(x::AbstractDict, schema, ::Val{:properties}, val::AbstractDict, path::String)
    for (k, v) in x
        if haskey(val, k)
            ret = _validate(v, val[k], path * "[$(k)]")
            if ret !== nothing
                return ret
            end
        end
    end
    return
end

# 9.3.2.2
function _validate(x::AbstractDict, schema, ::Val{:patternProperties}, val::AbstractDict, path::String)
    for (k_val, v_val) in val
        r = Regex(k_val)
        for (k_x, v_x) in x
            if match(r, k_x) === nothing
                continue
            end
            ret = _validate(v_x, v_val, path * "[$(k_x)")
            if ret !== nothing
                return ret
            end
        end
    end
    return
end

# 9.3.2.3
function _validate(x::AbstractDict, schema, ::Val{:additionalProperties}, val::AbstractDict, path::String)
    properties = get(schema, "properties", Dict{String,Any}())
    patternProperties = get(schema, "patternProperties", Dict{String,Any}())
    for (k, v) in x
        if k in keys(properties) || any(r -> match(Regex(r), k) !== nothing, keys(patternProperties))
            continue
        end
        ret = _validate(v, val, path * "[$(k)]")
        if ret !== nothing
            return ret
        end
    end
    return
end

function _validate(x::AbstractDict, schema, ::Val{:additionalProperties}, val::Bool, path::String)
    if val
        return
    end
    properties = get(schema, "properties", Dict{String,Any}())
    patternProperties = get(schema, "patternProperties", Dict{String,Any}())
    for (k, v) in x
        if k in keys(properties) || any(r -> match(Regex(r), k) !== nothing, keys(patternProperties))
            continue
        end
        return SingleIssue(x, path, "additionalProperties", val)
    end
    return
end

# 9.3.2.4: unevaluatedProperties

# 9.3.2.5
function _validate(x::AbstractDict, schema, ::Val{:propertyNames}, val, path::String)
    for k in keys(x)
        ret = _validate(k, val, path)
        if ret !== nothing
            return ret
        end
    end
    return
end

###
### Checks for generic types.
###

# 6.1.1
function _validate(x, schema, ::Val{:type}, val::String, path::String)
    return !_is_type(x, Val{Symbol(val)}()) ? SingleIssue(x, path, "type", val) : nothing
end

function _validate(x, schema, ::Val{:type}, val::Vector, path::String)
    if !any(v -> _is_type(x, Val{Symbol(v)}()), val)
        return SingleIssue(x, path, "type", val)
    end
    return
end

_is_type(::Any, ::Val) = false
_is_type(::Array, ::Val{:array}) = true
_is_type(::Bool, ::Val{:boolean}) = true
_is_type(::Integer, ::Val{:integer}) = true
_is_type(::Real, ::Val{:number}) = true
_is_type(::Nothing, ::Val{:null}) = true
_is_type(::Missing, ::Val{:null}) = true
_is_type(::AbstractDict, ::Val{:object}) = true
_is_type(::String, ::Val{:string}) = true
# Note that Julia treat's Bool <: Number, but JSON-Schema distinguishes them.
_is_type(::Bool, ::Val{:number}) = false
_is_type(::Bool, ::Val{:integer}) = false

# 6.1.2
function _validate(x, schema, ::Val{:enum}, val, path::String)
    return !any(x == v for v in val) ? SingleIssue(x, path, "enum", val) : nothing
end

# 6.1.3
function _validate(x, schema, ::Val{:const}, val, path::String)
    return x != val ? SingleIssue(x, path, "const", val) : nothing
end

###
### Checks for numbers.
###

# 6.2.1
function _validate(x::Number, schema, ::Val{:multipleOf}, val::Number, path::String)
    y = isapprox(x / val, round(x / val))
    return !y ? SingleIssue(x, path, "multipleOf", val) : nothing
end

# 6.2.2
function _validate(x::Number, schema, ::Val{:maximum}, val::Number, path::String)
    return x > val ? SingleIssue(x, path, "maximum", val) : nothing
end

# 6.2.3
function _validate(x::Number, schema, ::Val{:exclusiveMaximum}, val::Number, path::String)
    return x >= val ? SingleIssue(x, path, "exclusiveMaximum", val) : nothing
end

function _validate(x::Number, schema, ::Val{:exclusiveMaximum}, val::Bool, path::String)
    if !val
        return
    end
    max = get(schema, "maximum", Inf)
    return x >= max ? SingleIssue(x, path, "exclusiveMaximum", val) : nothing
end

# 6.2.4
function _validate(x::Number, schema, ::Val{:minimum}, val::Number, path::String)
    return x < val ? SingleIssue(x, path, "minimum", val) : nothing
end

# 6.2.5
function _validate(x::Number, schema, ::Val{:exclusiveMinimum}, val::Number, path::String)
    return x <= val ? SingleIssue(x, path, "exclusiveMinimum", val) : nothing
end

function _validate(x::Number, schema, ::Val{:exclusiveMinimum}, val::Bool, path::String)
    if !val
        return
    end
    max = get(schema, "minimum", -Inf)
    return x <= max ? SingleIssue(x, path, "exclusiveMinimum", val) : nothing
end


###
### Checks for strings.
###

# 6.3.1
function _validate(x::String, schema, ::Val{:maxLength}, val::Integer, path::String)
    return length(x) > val ? SingleIssue(x, path, "maxLength", val) : nothing
end

# 6.3.2
function _validate(x::String, schema, ::Val{:minLength}, val::Integer, path::String)
    return length(x) < val ? SingleIssue(x, path, "minLength", val) : nothing
end

# 6.3.3
function _validate(x::String, schema, ::Val{:pattern}, val::String, path::String)
    y = occursin(Regex(val), x)
    return !y ? SingleIssue(x, path, "pattern", val) : nothing
end

###
### Checks for arrays.
###

# 6.4.1
function _validate(x::Vector, schema, ::Val{:maxItems}, val::Integer, path::String)
    return length(x) > val ? SingleIssue(x, path, "maxItems", val) : nothing
end

# 6.4.2
function _validate(x::Vector, schema, ::Val{:minItems}, val::Integer, path::String)
    return length(x) < val ? SingleIssue(x, path, "minItems", val) : nothing
end

# 6.4.3
function _validate(x::Vector, schema, ::Val{:uniqueItems}, val::Bool, path::String)
    # It isn't sufficient to just compare allunique on x, because Julia treats 0 == false,
    # but JSON distinguishes them.
    y = [(xx, typeof(xx)) for xx in x]
    return val && !allunique(y) ? SingleIssue(x, path, "uniqueItems", val) : nothing
end

# 6.4.4: maxContains

# 6.4.5: minContains

###
### Checks for objects.
###

# 6.5.1
function _validate(x::AbstractDict, schema, ::Val{:maxProperties}, val::Integer, path::String)
    return length(x) > val ? SingleIssue(x, path, "maxProperties", val) : nothing
end

# 6.5.2
function _validate(x::AbstractDict, schema, ::Val{:minProperties}, val::Integer, path::String)
    return length(x) < val ? SingleIssue(x, path, "minProperties", val) : nothing
end

# 6.5.3
function _validate(x::AbstractDict, schema, ::Val{:required}, val::Vector, path::String)
    return any(v -> !haskey(x, v), val) ? SingleIssue(x, path, "required", val) : nothing
end

# 6.5.4
function _validate(x::AbstractDict, schema, ::Val{:dependencies}, val::AbstractDict, path::String)
    for (k, v) in val
        if !haskey(x, k)
            continue
        elseif !_dependencies(x, path, v)
            return SingleIssue(x, path, "dependencies", val)
        end
    end
    return
end

function _dependencies(x::AbstractDict, path::String, val::Union{Bool,Dict})
    return _validate(x, val, path) === nothing
end
_dependencies(x::AbstractDict, path::String, val::Array) = all(v -> haskey(x, v), val)
