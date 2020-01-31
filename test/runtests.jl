using BinaryProvider
using HTTP
using JSONSchema
using JSON
using Test

const TEST_SUITE_URL = "https://github.com/json-schema-org/JSON-Schema-Test-Suite/archive/2.0.0.tar.gz"

const SCHEMA_TEST_DIR = let
    dest_dir = mktempdir()
    dest_file = joinpath(dest_dir, "test-suite.tar.gz")
    BinaryProvider.download(TEST_SUITE_URL, dest_file, verbose = true)
    unzip_dir = joinpath(dest_dir, "test-suite")
    BinaryProvider.unpack(dest_file, unzip_dir)
    joinpath(unzip_dir, "JSON-Schema-Test-Suite-2.0.0", "tests")
end

const LOCAL_TEST_DIR = mktempdir(SCHEMA_TEST_DIR)

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
    "properties": {
        "localRefOneResult": { "type": "string" }
    }
}""")

write(
    joinpath(REF_LOCAL_TEST_DIR, "localReferenceSchemaTwo.json"),
    """{
    "type": "object",
    "properties": {
        "localRefTwoResult": { "type": "number" }
    }
}""")

write(
    joinpath(REF_LOCAL_TEST_DIR, "nestedLocalReference.json"),
    """{
    "type": "object",
    "properties": {
        "result": { "\$ref": "file:localReferenceSchemaOne.json#/properties/localRefOneResult" }
    }
}""")

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
        "oneOf": [
            {
                "required": ["result1"]
            },
            {
                "required": ["result2"]
            }
        ]
    },
    "tests": [
        {
            "description": "reference only local schema 1",
            "data": {"result1": "some text" },
            "valid": true
        },
        {
            "description": "reference only local schema 2",
                "data": {"result2": 1234 },
                "valid": true
        },
        {
            "description": "incorrect reference to local schema 1",
                "data": { "result1": true },
                "valid": false
        },
        {
            "description": "reference neither local schemas",
                "data": { "result": true },
                "valid": false
        },
        {
            "description": "reference both local schemas",
            "data": {"result1": "some text", "result2": 500 },
            "valid": false
        }
    ]
}]""")

write(
    joinpath(LOCAL_TEST_DIR, "nestedLocalReferenceTest.json"),
    """[{
    "description": "test locally referenced schemas",
    "schema": {
        "type": "object",
        "properties": {
            "result": { "\$ref": "file:../$(basename(abspath(REF_LOCAL_TEST_DIR)))/nestedLocalReference.json#/properties/result" }
        }
    },
    "tests": [
        {
            "description": "nested reference, correct type",
            "data": {"result": "some text" },
            "valid": true
        },
        {
            "description": "nested reference, incorrect type",
            "data": {"result": 1234 },
            "valid": false
        }
    ]
}]""")

@testset "Draft 4/6" begin
    # Note(odow): I didn't want to use a mutable reference like this for the web-server.
    # The obvious thing to do is to start a new server for each value of `draft_folder`,
    # however, shutting down the webserver asynchronously doesn't play well with
    # testsets, and I spent far too long trying to figure out what was going on.
    # This is a simple hack until someone who knows more about this comes along...
    GLOBAL_TEST_DIR = Ref{String}("")
    server = HTTP.Sockets.listen(
        HTTP.Sockets.InetAddr(parse(HTTP.Sockets.IPAddr, "127.0.0.1"), 1234)
    )
    @async HTTP.listen("127.0.0.1", 1234; server = server, verbose = true) do http
        # Make sure to strip first character (`/`) from the target, otherwise it will
        # infer as a file in the root directory.
        file = joinpath(GLOBAL_TEST_DIR[], "../../remotes", http.message.target[2:end])
        HTTP.setstatus(http, 200)
        startwrite(http)
        write(http, read(file, String))
    end
    @testset "$(draft_folder)" for draft_folder in [
        "draft4", "draft6", basename(abspath(LOCAL_TEST_DIR))
    ]
        test_dir = joinpath(SCHEMA_TEST_DIR, draft_folder)
        GLOBAL_TEST_DIR[] = test_dir
        @testset "$tfn" for tfn in filter(n -> occursin(r"\.json$",n), readdir(test_dir))
            fn = joinpath(test_dir, tfn)
            @testset "- $(subschema["description"])" for subschema in (JSON.parsefile(fn))
                dir = subschema["schema"] isa Bool ? abspath(".") : dirname(fn)
                spec = Schema(subschema["schema"]; parentFileDirectory = dir)
                @testset "* $(subtest["description"])" for subtest in subschema["tests"]
                    @test isvalid(subtest["data"], spec) == subtest["valid"]
                end
            end
        end
    end
    close(server)
end

@testset "Validate and diagnose" begin
    schema = Schema(
        Dict(
            "properties" => Dict(
                "foo" => Dict(),
                "bar" => Dict()
            ),
            "required" => ["foo"]
        )
    )
    data_pass = Dict("foo" => true)
    data_fail = Dict("bar" => 12.5)
    @test JSONSchema.validate(data_pass, schema) === nothing
    ret = JSONSchema.validate(data_fail, schema)
    fail_msg = """Validation failed:
    path:         top-level
    instance:     $(data_fail)
    schema key:   required
    schema value: ["foo"]
    """
    @test ret !== nothing
    @test sprint(show, ret) == fail_msg
    @test diagnose(data_pass, schema) === nothing
    @test diagnose(data_fail, schema) == fail_msg
end

@testset "Schemas" begin
    schema = Schema("""
    {
        \"properties\": {
        \"foo\": {},
        \"bar\": {}
        },
        \"required\": [\"foo\"]
    }
    """)
    @test typeof(schema) == Schema
    @test typeof(schema.data) == Dict{String,Any}

    schema_2 = Schema(false)
    @test typeof(schema_2) == Schema
    @test typeof(schema_2.data) == Bool
end
