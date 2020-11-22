# JSONSchema

_JSON instance validation using JSON Schemas_

[![Build Status](https://github.com/fredo-dedup/JSONSchema.jl/workflows/CI/badge.svg?branch=master)](https://github.com/fredo-dedup/JSONSchema.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/fredo-dedup/JSONSchema.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/fredo-dedup/JSONSchema.jl)

## Overview

[JSONSchema.jl](https://github.com/fredo-dedup/JSONSchema.jl) is a JSON validation package
for the [julia](https://julialang.org/) programming language. Given a [validation
schema](http://json-schema.org/specification.html) this package can verify if any JSON
instance meets all the assertions defining a valid document.

This package has been validated with the [JSON Schema Test Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite)
for draft v4 and v6.

## API

Create a `Schema` object by passing a string:
```julia
julia> my_schema = Schema("""{
            "properties": {
                "foo": {},
                "bar": {}
            },
            "required": ["foo"]
        }""")
```
passing a dictionary with the same structure as a schema:
```julia
julia> my_schema = Schema(
            Dict(
                "properties" => Dict(
                    "foo" => Dict(),
                    "bar" => Dict()
                ),
                "required" => ["foo"]
            )
        )
```
or by passing a parsed JSON file containing the schema:
```julia
julia> my_schema = Schema(JSON.parsefile(filename))
```

Check the validity of a given JSON instance by calling `validate` with the JSON instance `x`
to be tested and the `schema`. If the validation succeeds, `validate` returns `nothing`:
```julia
julia> data_pass = Dict("foo" => true)
Dict{String,Bool} with 1 entry:
  "foo" => true

julia> validate(data_pass, my_schema)

```

If the validation fails, a struct is returned that, when printed, explains the reason for
the failure:
```julia
julia> data_fail = Dict("bar" => 12.5)
Dict{String,Float64} with 1 entry:
  "bar" => 12.5

julia> validate(data_fail, my_schema)
Validation failed:
path:         top-level
instance:     Dict("bar"=>12.5)
schema key:   required
schema value: ["foo"]
```

As a short-hand for `validate(x, schema) === nothing`, use `Base.isvalid(x, schema)`.
