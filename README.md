# JSONSchema

_JSON instance validation using JSON Schemas_

[![Build Status](https://travis-ci.org/fredo-dedup/JSONSchema.jl.svg?branch=master)](https://travis-ci.org/fredo-dedup/JSONSchema.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/e6ea72l7sbll1via/branch/master?svg=true)](https://ci.appveyor.com/project/fredo-dedup/jsonschema/branch/master)
[![Coverage Status](https://coveralls.io/repos/github/fredo-dedup/JSONSchema/badge.svg?branch=master)](https://coveralls.io/github/fredo-dedup/JSONSchema?branch=master)
[![codecov](https://codecov.io/gh/fredo-dedup/JSONSchema.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/fredo-dedup/JSONSchema.jl)

## Overview

[JSONSchema.jl](https://github.com/fredo-dedup/JSONSchema.jl) is a JSON validation package for the [julia](https://julialang.org/) programming language. Given a validation Schema (see http://json-schema.org/specification.html) this package can verify if any JSON instance follows all the assertions defining a valid document.

This package has been validated with the test suite of the JSON Schema org (https://github.com/json-schema-org/JSON-Schema-Test-Suite) for draft v4 and v6.


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
isvalid( JSON.parse("{ "foo": true }"), myschema) # true
isvalid( JSON.parse("{ "bar": 12.5 }"), myschema) # false
```
The JSON instance should be provided as a pre-processed `JSON` object created
with the `JSON` package.


Should you need a diagnostic message to understand the cause of rejection you
can use the `diagnose()` function. `diagnose()` will either return `nothing`
if the instance is valid or a message detailing which assertion failed.
```julia
diagnose( JSON.parse("{ "foo": true }") , myschema)
# nothing
diagnose( JSON.parse("{ "bar": 12.5 }") , myschema)
# "in [] : required property 'foo' missing"
```
