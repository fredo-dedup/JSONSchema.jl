# JSONSchema

_JSON instance validation using JSON Schemas_

[![Build Status](https://travis-ci.org/fredo-dedup/JSONSchema.jl.svg?branch=master)](https://travis-ci.org/fredo-dedup/JSONSchema.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/b9cmmaquuc08n6uc/branch/master?svg=true)](https://ci.appveyor.com/project/fredo-dedup/vegalite-jl/branch/master)
[![VegaLite](http://pkg.julialang.org/badges/VegaLite_0.6.svg)](http://pkg.julialang.org/?pkg=VegaLite&ver=0.6)
[![Coverage Status](https://coveralls.io/repos/github/fredo-dedup/JSONSchema.jl/badge.svg?branch=master)](https://coveralls.io/github/fredo-dedup/JSONSchema.jl?branch=master)
[![codecov](https://codecov.io/gh/fredo-dedup/JSONSchema.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/fredo-dedup/JSONSchema.jl)

## Overview

[JSONSchema.jl](https://github.com/fredo-dedup/JSONSchema.jl) is a JSON validation package for the [julia](https://julialang.org/) programming language. The conformity to the JSON Schema standard is validated by using the test suite of the JSON Schema org (https://github.com/json-schema-org/JSON-Schema-Test-Suite).

## API

First step is to create a `Schema` object :
```julia
# using a String as input
myschema = Schema("""
 {
    "properties": {
       "foo": {},
       "bar": {}
    },
    "required": ["foo"]
 }""")  

# or using a pre-processed JSON as input, using the JSON package
sch = JSON.parsefile(filepath)
myschema = Schema(sch)
```

You can then check the validity of a given JSON instance by calling `isvalid`
with the JSON instance to be tested and the `Schema`:
```julia
isvalid("{ "foo": true }", myschema) # true
isvalid("{ "bar": 12.5 }", myschema) # false
```
The JSON instance to be tested can be provided as a String or a pre-processed
`JSON`
processed instance.


Should you need a diagnostic message with the validation, you can use the
`diagnose()` function which will return either `nothing` if the instance is
valid or a message detailing which assertion failed (with a differing degrees
  of detail controlled by the `verbose` option).
```julia
diagnose("{ "foo": true }", myschema) # nothing
diagnose("{ "bar": 12.5 }", myschema)
# xxxxx
```
