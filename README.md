# JSONSchema.jl

[![Build Status](https://github.com/fredo-dedup/JSONSchema.jl/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/fredo-dedup/JSONSchema.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/fredo-dedup/JSONSchema.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/fredo-dedup/JSONSchema.jl)

## Overview

[JSONSchema.jl](https://github.com/fredo-dedup/JSONSchema.jl) is a JSON
validation package for the [Julia](https://julialang.org/) programming language.
Given a [validation schema](http://json-schema.org/specification.html), this
package can verify if a JSON instance meets all the assertions that define a
valid document.

This package runs the
[JSON Schema Test Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite)
for drafts 4, 6, 7, 2019-09, and 2020-12. The `Schema` API remains the stable
compatibility API. The qualified `JSONSchema.CompiledSchema` API provides the
dialect-aware resource model described below.

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

Check the validity of a parsed JSON instance by calling `validate` with the JSON
instance `x` to be tested and the `schema`.

If the validation succeeds, `validate` returns `nothing`:
```julia
julia> document = """{"foo": true}""";

julia> data_pass = JSON.parse(document)
Dict{String,Bool} with 1 entry:
  "foo" => true

julia> validate(my_schema, data_pass)

```

By default, if the validation fails, a struct is returned that, when printed,
explains the reason for the failure:
```julia
julia> data_fail = Dict("bar" => 12.5)
Dict{String,Float64} with 1 entry:
  "bar" => 12.5

julia> validate(my_schema, data_fail)
Validation failed:
path:         top-level
instance:     Dict("bar"=>12.5)
schema key:   required
schema value: ["foo"]
```

Pass `fail_fast = false` to collect every validation issue in one pass. In this
mode, `validate` returns a vector of issue structs, or an empty vector when the
instance is valid:
```julia
julia> issues = validate(my_schema, data_fail; fail_fast = false)
1-element Vector{JSONSchema.SingleIssue}:
 Validation failed:
path:         top-level
instance:     Dict("bar"=>12.5)
schema key:   required
schema value: ["foo"]
```

As a short-hand for `validate(schema, x) === nothing`, use
`Base.isvalid(schema, x)`

Note that if `x` is a `String` in JSON format, you must use `JSON.parse(x)`
before passing to `validate`, that is, JSONSchema operates on the parsed
representation, not on the underlying `String` representation of the JSON data.

Generate a `Schema` object from a Julia type by calling `JSONSchema.schema`:
```julia
julia> params = JSONSchema.schema(
           @NamedTuple{query::String, limit::Union{Nothing,Int}};
           additionalProperties = false,
       )
A JSONSchema

julia> JSONSchema.spec(params)["required"]
1-element Vector{String}:
 "query"
```

`JSONSchema.schema` is intentionally not exported, to avoid clashing with common
names in user code. The initial generator is intended for simple typed API
parameters. It supports `NamedTuple`s, concrete structs, JSON scalar types,
vectors, dictionaries, tuples, and nullable unions such as
`Union{Nothing,String}`.

The generator emits an inline subset of JSON Schema that is valid for draft v7
by default: `type`, `properties`, `required`, `additionalProperties`, `items`,
`additionalItems`, `anyOf`, and nullable primitive type arrays. Passing `draft`
sets the generated `"$schema"` URI; draft 2019-09 and 2020-12 also use
`prefixItems` for tuple schemas. The generator does not infer validation
constraints such as string patterns, numeric ranges, formats, enums, recursive
references, or schema definitions.

Generated schemas are returned as ordinary `Schema` objects; the underlying
dictionary is available as `.data` or through `JSONSchema.spec(params)`, and
`JSON.json(params)` serializes the generated schema.

## Dialect-aware compilation

Use `JSONSchema.CompiledSchema` when a schema uses modern dialects, external
resources, anchors, dynamic references, or embedded schema resources. This API
is not exported. The narrow export surface remains `Schema` and `validate`.

```julia
schema = JSONSchema.CompiledSchema(
    Dict(
        "\$schema" => JSONSchema.DRAFT202012.uri,
        "type" => "array",
        "items" => Dict("type" => "integer"),
    ),
)

isvalid(schema, [1, 2, 3])
```

Compilation does not change the input value. It creates read-only resources,
resolves every reachable reference, checks supported keyword shapes, and
compiles regular expressions before validation. External retrieval is disabled
by default. Supply an explicit retriever when references can leave the initial
resource:

```julia
const Resources = JSONSchema.Resources

retriever = Resources.MemoryRetriever(
    Dict("https://example.com/integer" => "{\"type\":\"integer\"}"),
)
schema = JSONSchema.CompiledSchema(
    Dict("\$ref" => "https://example.com/integer");
    retriever,
)
```

`Resources.FileRetriever` accepts one or more allowed roots and a byte limit.
It rejects other URI schemes and paths outside those roots. Applications can
define another `Resources.AbstractRetriever` and implement
`Resources.retrieve` for a controlled retrieval policy.

A schema can also start at a JSON Pointer inside a larger JSON resource. This
keeps the surrounding resource available for references. If the pointer passes
through JSON Schema container keywords such as `\$defs`, compilation applies
the enclosing schema dialects and identifiers. Other surrounding document
members remain opaque:

```julia
resource = Resources.Resource(
    Resources.ResourceId("https://example.com/document.json"),
    parsed_document,
)
schema = JSONSchema.CompiledSchema(
    resource,
    Resources.JSONPointer("/schemas/Widget");
    dialect = JSONSchema.DRAFT202012,
)
```

Compilation is bounded by `max_resources`, `max_nodes`, and `max_depth`.
Validation is bounded by `max_evaluations`, `max_issues`, and `max_depth`.
Reference cycles that do not make progress raise `JSONSchema.EvaluationError`
instead of receiving an arbitrary validation result.

The compiled validator treats `format` as an annotation. It rejects a custom
dialect that requires the 2020-12 format-assertion vocabulary because this
package does not implement that vocabulary. Validation issue paths from the
compiled API use RFC 6901 JSON Pointer syntax.
