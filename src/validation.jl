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


@macroexpand( :( @report x path "eeereuuurr" ))

function tst(x, path)
  if x > 0.
    @report x path "not good $x"
  end
end

tst(12, ["here","here"])
tst(-1, ["here","here"])


struct SingleIssue  # validation issue reporting structure
  x                     # subJSON with validation issue
  path::Vector{String}  # JSPointer to x
  msg::String           # error message
end

struct OneOfIssue  # validation issue reporting structure
  path::Vector{String}  # JSPointer to x
  issues::Vector{Issue} # potential issues, collectively making the present issue
end


function check(x, s::Dict)
  evaluate(x, s) == nothing
end
check(x, s::Schema) = check(x, s.data)

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

# s = spec
evaluate(x, s::Schema) = evaluate(x, s.data)
# x, asserts = subtest["data"], s.data;
# x = x["foo"]
# asserts = asserts["properties"]["foo"];

### check for assertions applicable to arrays
function array_asserts(x, asserts, path)
  @doassert asserts "items" begin
    if keyval isa Dict
      any( !check(el, keyval) for el in x ) && return "not an array of $keyval"
    elseif keyval isa Array
      for (i, iti) in enumerate(keyval)
        i > length(x) && break
        check(x[i], iti) || return "not a $iti at pos $i"
      end
      if haskey(asserts, "additionalItems") && (length(keyval) < length(x))
        addit = asserts["additionalItems"]
        if addit isa Bool
          (addit == false) && return "additional items not allowed"
        else
          for i in length(keyval)+1:length(x)
            check(x[i], addit) || return "not a $addit at pos $i"
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
    if ! any(check(el, keyval) for el in x)
      
      @report x path "does not contain $keyval"
  end

  nothing
end


function evaluate(x, asserts::Dict)

  # if a ref is present, it should supersede all sibling properties
  refhistory = Any[asserts];
  while isa(asserts, Dict) && haskey(asserts, "\$ref") # resolve nested refs until an end is found
    asserts = asserts["\$ref"]
    (asserts in refhistory) && error("circular references in schema")
    push!(refhistory, asserts)
  end

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

  @doassert asserts "enum" begin
    any(x == e for e in keyval) || return "expected to be one of $en"
  end

  if isa(x, Array)
    @doassert asserts "items" begin
      if keyval isa Dict
        any( !check(el, keyval) for el in x ) && return "not an array of $keyval"
      elseif keyval isa Array
        for (i, iti) in enumerate(keyval)
          i > length(x) && break
          check(x[i], iti) || return "not a $iti at pos $i"
        end
        if haskey(asserts, "additionalItems") && (length(keyval) < length(x))
          addit = asserts["additionalItems"]
          if addit isa Bool
            (addit == false) && return "additional items not allowed"
          else
            for i in length(keyval)+1:length(x)
              check(x[i], addit) || return "not a $addit at pos $i"
            end
          end
        end
      end
    end

    @doassert asserts "maxItems" begin
      (length(x) <= keyval) || return "array longer than $keyval"
    end

    @doassert asserts "minItems" begin
      (length(x) >= keyval) || return "array shorter than $keyval"
    end

    @doassert asserts "uniqueItems" begin
      if keyval
        xt = [(xx, typeof(xx)) for xx in x] # to differentiate 1 & true
        (length(unique(hash.(xt))) == length(x)) || return "non unique elements"
        #FIXME avoid the collapse of 1 / true into 1
      end
    end

    @doassert asserts "contains" begin
      any(check(el, keyval) for el in x) || return "does not contain $keyval"
    end
  end

  if isa(x, Dict)

    if haskey(asserts, "dependencies")
      dep = asserts["dependencies"]
      for (k,v) in dep
        if haskey(x, k)
          if v isa Dict
            check(x, v) || return "is not a $v (dependency $k)"
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
    @doassert asserts "maxLength" begin
      (length(x) > keyval) && return "longer than $keyval characters"
    end

    @doassert asserts "minLength" begin
      (length(x) < keyval) && return "shorter than $keyval characters"
    end

    @doassert asserts "pattern" begin
      ismatch(Regex(keyval), x) || return "does not match pattern $keyval"
    end
  end


  @doassert asserts "allOf" begin
    all( check(x, subsch) for subsch in keyval ) ||
      return "does not satisfy all of $keyval"
  end

  @doassert asserts "anyOf" begin
    any( check(x, subsch) for subsch in keyval ) ||
      return "does not satisfy any of $keyval"
  end

  @doassert asserts "oneOf" begin
    (sum(check(x, subsch) for subsch in keyval)==1) ||
      return "does not satisfy one of $(join(keyval, "\n"))"
  end

  @doassert asserts "not" begin
    check(x, keyval) &&
      return "does not satisfy 'not' assertion $keyval"
  end

  nothing
end
