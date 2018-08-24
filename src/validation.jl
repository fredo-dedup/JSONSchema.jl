####################################################################
#  JSON validation
####################################################################

macro doassert(asserts::Symbol, key::String, block::Expr)
  quote
    if haskey($(esc(asserts)), $key)
      $(esc(:( keyval = ($asserts)[$key]) ))
      $(esc(block))
    end
  end
end

macro report(what, wher, msg)
  quote
    return SingleIssue($(esc(what)), $(esc(wher)), $(esc(msg)))
  end
end

abstract type AbstractIssue end

struct SingleIssue <: AbstractIssue  # validation issue reporting structure
  x                     # subJSON with validation issue
  path::Vector{String}  # JSPointer to x
  msg::String           # error message
end

struct OneOfIssue <: AbstractIssue # validation issue reporting structure
  path::Vector{String}  # JSPointer to x
  issues::Vector{<:AbstractIssue} # potential issues, collectively making the present issue
end

### type assertion
function type_asserts(x, typ::String, path)
  if typ == "string"
    x isa String || @report x path "is not a string"
  elseif typ == "number"
    (x isa Int) || (x isa Float64) || @report x path "is not a number"
  elseif typ == "integer"
    x isa Int || @report x path "is not an integer"
  elseif typ == "array"
    x isa Array || @report x path "is not an array"
  elseif typ == "boolean"
    x isa Bool || @report x path "is not a boolean"
  elseif typ == "object"
    x isa Dict || @report x path "is not an object"
  elseif typ == "null"
    (x == nothing) || @report x path "is not null"
  end
  nothing
end

### check for assertions applicable to arrays
function array_asserts(x, asserts, path)
  @doassert asserts "items" begin
    if (keyval isa Bool) && ! keyval
      (length(x) > 0) && @report x path "schema (=false) does not allow non-empty arrays"

    elseif keyval isa Dict
      for i in 1:length(x)
        ret = validate(x[i], keyval, [path; "$(i-1)"])
        (ret==nothing) || return ret
      end

    elseif keyval isa Array
      for (i, iti) in enumerate(keyval)
        i > length(x) && break
        ret = validate(x[i], iti, [path; "$(i-1)"])
        (ret==nothing) || return ret
      end

      if haskey(asserts, "additionalItems") && (length(keyval) < length(x))
        addit = asserts["additionalItems"]
        if addit isa Bool
          (addit == false) &&  @report x path "additional items not allowed"
        else
          for i in length(keyval)+1:length(x)
            ret = validate(x[i], addit, [path; "$(i-1)"])
            (ret==nothing) || return ret
          end
        end
      end
    end
  end

  @doassert asserts "maxItems" begin
    (length(x) <= keyval) ||
      @report x path "array longer than $keyval"
  end

  @doassert asserts "minItems" begin
    (length(x) >= keyval) ||
      @report x path "array shorter than $keyval"
  end

  @doassert asserts "uniqueItems" begin
    if keyval
      xt = [(xx, typeof(xx)) for xx in x]
      (length(unique(hash.(xt))) == length(x)) ||
        @report x path "non unique elements"
    end
  end

  @doassert asserts "contains" begin
    is = AbstractIssue[]
    oneOK = false
    for (i,el) in enumerate(x)
      ret = validate(el, keyval, [path; "$(i-1)"])
      (ret==nothing) && (oneOK = true; break)
      push!(is, ret)
    end
    oneOK || return OneOfIssue(path, is)
  end

  nothing
end

### check for assertions applicable to numbers
function number_asserts(x, asserts, path)
  @doassert asserts "multipleOf" begin
    δ = abs(x - keyval*round(x / keyval))
    (δ < eps(Float64)) || @report x path "not a multipleOf of $keyval"
  end

  @doassert asserts "maximum" begin
    (x <= keyval) || @report x path "not <= $keyval"
  end

  @doassert asserts "exclusiveMaximum" begin
    if (keyval isa Bool) && haskey(asserts, "maximum")  # draft 4
      val2 = asserts["maximum"]
      if keyval
        (x < val2) || @report x path "not < $val2"
      else
        (x <= val2) || @report x path "not <= $val2"
      end
    elseif keyval isa Number  # draft 6
      (x < keyval) || @report x path "not < $keyval"
    end
  end

  @doassert asserts "minimum" begin
    (x >= keyval) || @report x path "not >= $keyval"
  end

  @doassert asserts "exclusiveMinimum" begin
    if (keyval isa Bool) && haskey(asserts, "minimum")  # draft 4
      val2 = asserts["minimum"]
      if keyval
        (x > val2) || @report x path "not > $val2"
      else
        (x >= val2) || @report x path "not >= $val2"
      end
    elseif keyval isa Number
      (x > keyval) || @report x path "not > $keyval"
    end
  end

  nothing
end

### check for assertions applicable to strings
function string_asserts(x, asserts, path)
  @doassert asserts "maxLength" begin
    (length(x) > keyval) && @report x path "string longer than $keyval characters"
  end

  @doassert asserts "minLength" begin
    (length(x) < keyval) && @report x path "string shorter than $keyval characters"
  end

  @doassert asserts "pattern" begin
    occursin(Regex(keyval), x) || @report x path "string does not match pattern $keyval"
  end

  nothing
end

### check for assertions applicable to objects
function object_asserts(x, asserts, path)
  if haskey(asserts, "dependencies")
    dep = asserts["dependencies"]
    for (k,v) in dep
      if haskey(x, k)
        if (v isa Dict) || (v isa Bool)
          ret = validate(x, v, path)
          (ret == nothing) || return ret
        else
          for rk in v
            haskey(x, rk) || @report x path "required property '$rk' missing (dependency $k)"
          end
        end
      end
    end
  end

  @doassert asserts "propertyNames" begin
    if isa(keyval, Bool)
      if ! keyval
        (length(x) > 0) && @report x path "schema (=false) allows only empty objects here"
      end
    else
      for propname in keys(x)
        ret = string_asserts(propname, keyval , path)
        (ret==nothing) || return ret
      end
    end
  end

  @doassert asserts "maxProperties" begin
    (length(x) <= keyval) || @report x path "nb of properties > $keyval"
  end

  @doassert asserts "minProperties" begin
    (length(x) >= keyval) || @report x path "nb of properties < $keyval"
  end

  remainingprops = collect(keys(x))
  @doassert asserts "required" begin
    for k in keyval
      (k in remainingprops) || @report x path "required property '$k' missing"
    end
  end

  matchedprops = String[]
  if haskey(asserts, "patternProperties") && length(remainingprops) > 0
    patprop = asserts["patternProperties"]
    for k in remainingprops
      hasmatch = false
      for (rk, rtest) in patprop
        if occursin(Regex(rk), k)
          hasmatch = true
          ret = validate(x[k], rtest, [path; k])
          (ret == nothing) || return ret
          # "property $k matches pattern $rk but is not a $rtest"
        end
      end
      hasmatch && push!(matchedprops, k)
    end
  end

  if haskey(asserts, "properties")
    prop = asserts["properties"]
    for k in intersect(remainingprops, keys(prop))
      ret = validate(x[k], prop[k], [path; k])
      (ret == nothing) || return ret
      push!(matchedprops, k)
    end
  end

  remainingprops = setdiff(remainingprops, matchedprops)
  if haskey(asserts, "additionalProperties") && length(remainingprops) > 0
    addprop = asserts["additionalProperties"]
    if addprop isa Bool
      rpstr = join([ "`$p`" for p in remainingprops], ", ", " & ")
      (addprop == false) && @report x path "additional property(ies) $rpstr not allowed"
    else
      for k in remainingprops
        ret = validate(x[k], addprop, [path; k])
        (ret == nothing) || return ret
      end
    end
  end

  nothing
end


# s = spec
# for cases where there is no schema but a true/false (in allOf, etc..)
function validate(x, s::Bool, path=String[])
  s || @report x path "schema (=false) does not allow any value here"
  nothing
end


validate(x, s::Schema, path=String[]) = validate(x, s.data, path)
function validate(x, asserts::Dict, path=String[])
  # if a ref is present, it should supersede all sibling properties
  refhistory = Any[asserts];
  while isa(asserts, Dict) && haskey(asserts, "\$ref") # resolve nested refs until an end is found
    asserts = asserts["\$ref"]
    (asserts in refhistory) && error("circular references in schema")
    push!(refhistory, asserts)
  end
  isa(asserts, Bool) && return validate(x, asserts, path) # in case ref turns out to be a boolean


  @doassert asserts "type" begin
    if keyval isa Array
      any( type_asserts(x, typ2, path)==nothing for typ2 in keyval ) ||
        @report x path "is not any of the allowed types $keyval"
    else
      ret = type_asserts(x, keyval, path)
      (ret==nothing) || return ret
    end
  end

  @doassert asserts "enum" begin
    any(x == e for e in keyval) ||
      @report x path "expected to be one of $keyval"
  end

  @doassert asserts "const" begin
    expected = keyval==nothing ? "'nothing'" : keyval
    (x == keyval) || @report x path "expected to be equal to $expected"
  end

  if isa(x, Array)
    ret = array_asserts(x, asserts, path)
    (ret==nothing) || return ret
  end

  if isa(x, Dict)
    ret = object_asserts(x, asserts, path)
    (ret==nothing) || return ret
  end

  if (x isa Int) || (x isa Float64)  # a 'number' for JSON
    ret = number_asserts(x, asserts, path)
    (ret==nothing) || return ret
  end

  if x isa String
    ret = string_asserts(x, asserts, path)
    (ret==nothing) || return ret
  end

  @doassert asserts "allOf" begin
    for subsch in keyval
      ret = validate(x, subsch, path)
      (ret==nothing) || return ret
    end
  end

  @doassert asserts "anyOf" begin
    is = AbstractIssue[]
    oneOK = false
    for subsch in keyval
      ret = validate(x, subsch, path)
      (ret==nothing) && (oneOK = true; break)
      push!(is, ret)
    end
    oneOK || return OneOfIssue(path, is)
  end

  @doassert asserts "oneOf" begin
    is = AbstractIssue[]
    oneOK, moreOK = false, false
    for subsch in keyval
      ret = validate(x, subsch, path)
      if ret==nothing
        oneOK && (moreOK = true)
        oneOK = true
      else
        push!(is, ret)
      end
    end
    oneOK || return OneOfIssue(path, is)
    # TODO : improve reporting if more than one matches
    moreOK && @report x path "more than one match in a 'oneOf' clause"
  end

  @doassert asserts "not" begin
    ret = validate(x, keyval, path)
    (ret==nothing) && @report x path "does not satisfy 'not' assertion $keyval"
  end

  nothing
end



##############   user facing functions #########################

"""
`isvalid(x, s::Schema)`

Check that a document `x` is valid against the Schema `s`.

## Examples

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

julia> isvalid( JSON.parse("{ \"foo\": true }"), myschema)
true
julia> isvalid( JSON.parse("{ \"bar\": 12.5 }"), myschema)
false
```
"""
function isvalid(x, s::Schema)
  validate(x, s.data) == nothing
end



flatten(ofi::JSONSchema.OneOfIssue) = vcat([flatten(i) for i in ofi.issues]...)
flatten(si::JSONSchema.SingleIssue) = [si;]

singleissuerecap(si::JSONSchema.SingleIssue) =
    "in [$(join(si.path, '.'))] : $(si.msg)"


"""
`diagnose(x, s::Schema)`

Check that a document `x` is valid against the Schema `s`. If
valid return `nothing`, and if not, return a diagnostic String containing a
selection of one or more likely causes of failure.

## Examples

```julia
julia> diagnose( JSON.parse("{ \"foo\": true }"), myschema)
nothing
julia> diagnose( JSON.parse("{ \"bar\": 12.5 }"), myschema)
"in [] : required property 'foo' missing"
```
"""
function diagnose(x, s::Schema)
    hyps = JSONSchema.validate(x, s)
    (hyps == nothing) && return nothing

    hyps2 = flatten(hyps)

    # The selection heuristic is to keep only the issues appearing deeper in
    # the tree. This will trim out the 'oneOf' assertions that were not
    # intended in the first place in 'x' (hopefully).
    lmax = maximum(e -> length(e.path), hyps2)
    filter!(e -> length(e.path) == lmax, hyps2)

    if length(hyps2) == 1
        return singleissuerecap(hyps2[1])
    else
        msg = ["One of :";
               map(x -> "  - " * singleissuerecap(x), hyps2) ]
        return join(msg, "\n")
    end
    nothing
end
