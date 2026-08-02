# Copyright (c) 2026: fredo-dedup, quinnj, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using JSONSchema
using Test
import Downloads
import HTTP
import JSON
import JSON3
import OrderedCollections
import ZipFile

const TEST_SUITE_REVISION = "be54236db6e8e6bb2e098ed16fb4c61e73f5a9ac"
const TEST_SUITE_URL = "https://github.com/json-schema-org/JSON-Schema-Test-Suite/archive/$TEST_SUITE_REVISION.zip"

const SCHEMA_TEST_DIR = let
    dest_dir = mktempdir()
    dest_file = joinpath(dest_dir, "test-suite.zip")
    Downloads.download(TEST_SUITE_URL, dest_file)
    for f in ZipFile.Reader(dest_file).files
        filename = joinpath(dest_dir, "test-suite", f.name)
        if endswith(filename, "/")
            mkpath(filename)
        else
            write(filename, read(f, String))
        end
    end
    joinpath(
        dest_dir,
        "test-suite",
        "JSON-Schema-Test-Suite-$TEST_SUITE_REVISION",
        "tests",
    )
end

const LOCAL_TEST_DIR = mktempdir(SCHEMA_TEST_DIR)

include("resources.jl")
include("compiled.jl")

@testset "Compiled JSON3 interop" begin
    schema = JSONSchema.CompiledSchema(JSON3.read("{\"type\":\"object\"}"))
    @test isvalid(schema, JSON3.read("{}"))
    @test !isvalid(schema, JSON3.read("[]"))
    @test isempty(
        JSONSchema.validate(schema, JSON3.read("{}"); fail_fast = false),
    )
end

# Write test files for locally referenced schema files.
#
# These files have the same format as JSON Schema org test files. They are written
# to a sibling directory to JSON-Schema-Test-Suite-master/tests/draft* directories
# so they can be consumed the same way as the draft*/*.json test files.
# sibling directory for testing a relative path containing "../"
const REF_LOCAL_TEST_DIR = mktempdir(SCHEMA_TEST_DIR)

write(
    joinpath(REF_LOCAL_TEST_DIR, "localReferenceSchemaOne.json"),
    """{
    "type": "object",
    "properties": {"localRefOneResult": {"type": "string"}}
}""",
)

write(
    joinpath(REF_LOCAL_TEST_DIR, "localReferenceSchemaTwo.json"),
    """{
    "type": "object",
    "properties": {"localRefTwoResult": {"type": "number"}}
}""",
)

write(
    joinpath(REF_LOCAL_TEST_DIR, "nestedLocalReference.json"),
    """{
    "type": "object",
    "properties": {
        "result": {
            "\$ref": "file:localReferenceSchemaOne.json#/properties/localRefOneResult"
        }
    }
}""",
)

write(
    joinpath(LOCAL_TEST_DIR, "localReferenceTest.json"),
    """[{
    "description": "test locally referenced schemas",
    "schema": {
        "type": "object",
        "properties": {
            "result1": { "\$ref": "file:../$(basename(abspath(REF_LOCAL_TEST_DIR)))/localReferenceSchemaOne.json#/properties/localRefOneResult" },
            "result2": { "\$ref": "../$(basename(abspath(REF_LOCAL_TEST_DIR)))/localReferenceSchemaTwo.json#/properties/localRefTwoResult" }
        },
        "oneOf": [{
            "required": ["result1"]
        }, {
            "required": ["result2"]
        }]
    },
    "tests": [{
        "description": "reference only local schema 1",
        "data": {"result1": "some text"},
        "valid": true
    }, {
        "description": "reference only local schema 2",
        "data": {"result2": 1234},
        "valid": true
    }, {
        "description": "incorrect reference to local schema 1",
        "data": {"result1": true},
        "valid": false
    }, {
        "description": "reference neither local schemas",
        "data": {"result": true},
        "valid": false
    }, {
        "description": "reference both local schemas",
        "data": {"result1": "some text", "result2": 500},
        "valid": false
    }]
}]""",
)

write(
    joinpath(LOCAL_TEST_DIR, "nestedLocalReferenceTest.json"),
    """[{
    "description": "test locally referenced schemas",
    "schema": {
        "type": "object",
        "properties": {
            "result": {
                "\$ref": "file:../$(basename(abspath(REF_LOCAL_TEST_DIR)))/nestedLocalReference.json#/properties/result"
            }
        }
    },
    "tests": [{
        "description": "nested reference, correct type",
        "data": {"result": "some text"},
        "valid": true
    }, {
        "description": "nested reference, incorrect type",
        "data": {"result": 1234},
        "valid": false
    }]
}]""",
)

is_json(n) = endswith(n, ".json")

function test_draft_directory(server, dir, json_parse_fn::Function)
    @testset "$(file)" for file in filter(is_json, readdir(dir))
        if file == "unknownKeyword.json"
            # This is an optional test, and to be honest, it is pretty minor. It
            # relates to how we handle $id if the user includes part of a schema
            # that we don't know how to parse. As a low priority action item, we
            # could come back to this.
            continue
        end
        file_path = joinpath(dir, file)
        @testset "$(tests["description"])" for tests in json_parse_fn(file_path)
            # TODO(odow): fix this failing test
            fails =
                ["retrieved nested refs resolve relative to their URI not \$id"]
            if file == "refRemote.json" && tests["description"] in fails
                continue
            end
            is_bool = tests["schema"] isa Bool
            parent_dir = ifelse(is_bool, abspath("."), dirname(file_path))
            schema = JSONSchema.Schema(tests["schema"]; parent_dir)
            @testset "$(test["description"])" for test in tests["tests"]
                @test isvalid(schema, test["data"]) == test["valid"]
            end
        end
    end
    return
end

@testset "JSON-Schema-Test-Suite" begin
    GLOBAL_TEST_DIR = Ref{String}("")
    server = HTTP.Sockets.listen(HTTP.ip"127.0.0.1", 1234)
    HTTP.serve!("127.0.0.1", 1234; server = server) do req
        # Make sure to strip first character (`/`) from the target, otherwise it
        # will infer as a file in the root directory.
        file = joinpath(GLOBAL_TEST_DIR[], "../../remotes", req.target[2:end])
        return HTTP.Response(200, read(file, String))
    end
    @testset "$dir" for dir in [
        "draft4",
        "draft6",
        "draft7",
        basename(abspath(LOCAL_TEST_DIR)),
    ]
        GLOBAL_TEST_DIR[] = joinpath(SCHEMA_TEST_DIR, dir)
        @testset "JSON" begin
            test_draft_directory(server, GLOBAL_TEST_DIR[], JSON.parsefile)
        end
        @testset "JSON3" begin
            test_draft_directory(server, GLOBAL_TEST_DIR[], JSON3.read)
        end
    end
    close(server)
end

@testset "Validate and diagnose" begin
    schema = JSONSchema.Schema(
        Dict(
            "properties" => Dict("foo" => Dict(), "bar" => Dict()),
            "required" => ["foo"],
        ),
    )
    data_pass = Dict("foo" => true)
    data_fail = Dict("bar" => 12.5)
    @test JSONSchema.validate(schema, data_pass) === nothing
    ret = JSONSchema.validate(schema, data_fail)
    fail_msg = """Validation failed:
    path:         top-level
    instance:     $(data_fail)
    schema key:   required
    schema value: ["foo"]
    """
    @test ret !== nothing
    @test sprint(show, ret) == fail_msg
    @test JSONSchema.diagnose(data_pass, schema) === nothing
    @test JSONSchema.diagnose(data_fail, schema) == fail_msg
end

@testset "Validate all issues" begin
    schema = JSONSchema.Schema(
        Dict(
            "properties" => Dict(
                "Title" => Dict("type" => "string"),
                "Desc" => Dict("type" => "string"),
            ),
        ),
    )
    data = Dict("Title" => nothing, "Desc" => 15)

    @test JSONSchema.validate(schema, data) isa JSONSchema.SingleIssue
    issues = JSONSchema.validate(schema, data; fail_fast = false)
    @test issues isa Vector{JSONSchema.SingleIssue}
    @test Set(issue.path for issue in issues) == Set(["[Title]", "[Desc]"])
    @test all(issue.reason == "type" for issue in issues)

    @test JSONSchema.validate(data, schema; fail_fast = false) == issues
    @test isempty(
        JSONSchema.validate(schema, Dict("Title" => "ok"); fail_fast = false),
    )

    allof_schema = JSONSchema.Schema(
        Dict(
            "allOf" => [
                Dict("properties" =>
                        Dict("name" => Dict("type" => "string"))),
                Dict("properties" => Dict("count" => Dict("minimum" => 2))),
            ],
        ),
    )
    issues = JSONSchema.validate(
        allof_schema,
        Dict("name" => 1, "count" => 1);
        fail_fast = false,
    )
    @test Set((issue.path, issue.reason) for issue in issues) ==
          Set([("[name]", "type"), ("[count]", "minimum")])

    conditional_schema = JSONSchema.Schema(
        Dict(
            "if" => Dict(
                "properties" => Dict("kind" => Dict("const" => "full")),
            ),
            "then" => Dict(
                "properties" => Dict(
                    "name" => Dict("type" => "string"),
                    "count" => Dict("type" => "integer"),
                ),
            ),
        ),
    )
    issues = JSONSchema.validate(
        conditional_schema,
        Dict("kind" => "full", "name" => 1, "count" => "many");
        fail_fast = false,
    )
    @test Set(issue.path for issue in issues) == Set(["[name]", "[count]"])
end

@testset "parentFileDirectory deprecation" begin
    schema = JSONSchema.Schema("{}"; parentFileDirectory = ".")
    @test typeof(schema) == Schema
end

@testset "Schemas" begin
    schema = JSONSchema.Schema("""{
        \"properties\": {
        \"foo\": {},
        \"bar\": {}
        },
        \"required\": [\"foo\"]
    }""")
    @test typeof(schema) == Schema
    @test typeof(schema.data) <: AbstractDict{String,Any}
    schema_2 = JSONSchema.Schema(false)
    @test typeof(schema_2) == Schema
    @test typeof(schema_2.data) == Bool

    schema_dict = Dict(
        "properties" =>
            Dict("age" => Dict("\$ref" => "#/\$defs/positiveNumber")),
        "\$defs" => Dict(
            "positiveNumber" => Dict("type" => "number", "minimum" => 0),
        ),
    )
    schema = JSONSchema.Schema(schema_dict)
    @test isvalid(schema, Dict("age" => 1))
    @test !isvalid(schema, Dict("age" => -1))
    @test schema_dict["properties"]["age"]["\$ref"] == "#/\$defs/positiveNumber"
end

@testset "Base.show" begin
    schema = JSONSchema.Schema("{}")
    @test sprint(show, schema) == "A JSONSchema"
end

@testset "errors" begin
    @test_throws(
        ErrorException("missing property 'Foo' in $(JSON.parse("{}"))."),
        JSONSchema.Schema("""{
            "type": "object",
            "properties": {"version": {"\$ref": "#/definitions/Foo"}},
            "definitions": {}
        }"""),
    )
    @test_throws(
        ErrorException("unmanaged type in ref resolution $(Int64): 1."),
        JSONSchema.Schema("""{
            "type": "object",
            "properties": {"version": {"\$ref": "#/definitions/Foo"}},
            "definitions": 1
        }""")
    )
    @test_throws(
        ErrorException("expected integer array index instead of 'Foo'."),
        JSONSchema.Schema("""{
            "type": "object",
            "properties": {"version": {"\$ref": "#/definitions/Foo"}},
            "definitions": [1, 2]
        }""")
    )
    @test_throws(
        ErrorException("item index 3 is larger than array $(Any[1, 2])."),
        JSONSchema.Schema("""{
            "type": "object",
            "properties": {"version": {"\$ref": "#/definitions/3"}},
            "definitions": [1, 2]
        }""")
    )
    @test_throws(
        ErrorException("cannot support circular references in schema."),
        JSONSchema.validate(
            JSONSchema.Schema("""{
                "type": "object",
                "properties": {
                    "version": {
                        "\$ref": "#/definitions/Foo"
                    }
                },
                "definitions": {
                    "Foo": {
                        "\$ref": "#/definitions/Foo"
                    }
                }
            }"""),
            Dict("version" => 1),
        )
    )
end

@testset "_is_type" begin
    for (key, val) in Dict(
        :array => [1, 2],
        :boolean => true,
        :integer => 1,
        :number => 1.0,
        :null => nothing,
        :object => Dict(),
        :string => "string",
    )
        @test JSONSchema._is_type(val, Val(Symbol(key)))
        @test !JSONSchema._is_type(:not_a_json_type, Val(Symbol(key)))
    end
    @test JSONSchema._is_type(missing, Val(:null))

    @test !JSONSchema._is_type(true, Val(:number))
    @test !JSONSchema._is_type(true, Val(:integer))
end

@testset "OrderedDict" begin
    schema = JSONSchema.Schema(
        Dict(
            "properties" => Dict("foo" => Dict(), "bar" => Dict()),
            "required" => ["foo"],
        ),
    )
    data_pass = OrderedCollections.OrderedDict("foo" => true)
    data_fail = OrderedCollections.OrderedDict("bar" => 12.5)
    @test JSONSchema.validate(schema, data_pass) === nothing
    @test JSONSchema.validate(schema, data_fail) != nothing
end

@testset "Inverse argument order" begin
    schema = JSONSchema.Schema(
        Dict(
            "properties" => Dict("foo" => Dict(), "bar" => Dict()),
            "required" => ["foo"],
        ),
    )
    data_pass = Dict("foo" => true)
    data_fail = Dict("bar" => 12.5)
    @test JSONSchema.validate(data_pass, schema) === nothing
    @test JSONSchema.validate(data_fail, schema) != nothing
    @test isvalid(data_pass, schema)
    @test !isvalid(data_fail, schema)
end

@testset "exports" begin
    @test Schema === JSONSchema.Schema
    @test validate === JSONSchema.validate
    @test diagnose === JSONSchema.diagnose
    @test !(:schema in names(JSONSchema))
    @test !(:spec in names(JSONSchema))
    @test JSONSchema.schema(@NamedTuple{x::String}) isa JSONSchema.Schema
end

include("generation.jl")
