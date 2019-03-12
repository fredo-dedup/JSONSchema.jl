using JSONSchema, JSON
import BinaryProvider

using Test

### load the "json-schema-org/JSON-Schema-Test-Suite" project from github
tsurl = "https://github.com/json-schema-org/JSON-Schema-Test-Suite/archive/master.tar.gz"

destdir = mktempdir()
dwnldfn = joinpath(destdir, "test-suite.tar.gz")
BinaryProvider.download(tsurl, dwnldfn, verbose=true)

unzipdir = joinpath(destdir, "test-suite")
BinaryProvider.unpack(dwnldfn, unzipdir)

jsonTestFilesDirectory = joinpath(unzipdir, "JSON-Schema-Test-Suite-master", "tests")
localReferenceTestsDirectory = mktempdir(jsonTestFilesDirectory)


"""
Write test files for locally referenced schema files.
These files have the same format as JSON Schema org test files. They are written 
to a sibling directory to JSON-Schema-Test-Suite-master/tests/draft* directories 
so they can be consumed the same way as the draft*/*.json test files.
"""
function writeLocalReferenceTestFiles()
    # sibling directory for testing a relative path containing "../"
    referenceComponentsDirectory = mktempdir(jsonTestFilesDirectory)

    write(joinpath(referenceComponentsDirectory, "localReferenceSchemaOne.json"), """
    {
        "type": "object",
        "properties": {
            "localRefOneResult": { "type": "string" }
        }
    }
    """)
    
    write(joinpath(referenceComponentsDirectory, "localReferenceSchemaTwo.json"), """
    {
        "type": "object",
        "properties": {
            "localRefTwoResult": { "type": "number" }
        }
    }
    """)
    
    write(joinpath(referenceComponentsDirectory, "nestedLocalReference.json"), """
    {
        "type": "object",
        "properties": {
            "result": { "\$ref": "file:localReferenceSchemaOne.json#/properties/localRefOneResult" }
        }
    }
    """)
    
    write(joinpath(localReferenceTestsDirectory, "localReferenceTest.json"), """[
    {
        "description": "test locally referenced schemas",
        "schema": {
            "type": "object",
            "properties": {
                "result1": { "\$ref": "file:../$(basename(abspath(referenceComponentsDirectory)))/localReferenceSchemaOne.json#/properties/localRefOneResult" },
                "result2": { "\$ref": "../$(basename(abspath(referenceComponentsDirectory)))/localReferenceSchemaTwo.json#/properties/localRefTwoResult" }
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
    }
    ]""")
    
    write(joinpath(localReferenceTestsDirectory, "nestedLocalReferenceTest.json"), """[
    {
        "description": "test locally referenced schemas",
        "schema": {
            "type": "object",
            "properties": {
                "result": { "\$ref": "file:../$(basename(abspath(referenceComponentsDirectory)))/nestedLocalReference.json#/properties/result" }
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
    }
    ]""")
    # return directory name (not path) of tests for use in testing below
    return 
end


writeLocalReferenceTestFiles()


@testset begin

    ################################################################################
    ### Applying test suites for draft 4/6 specifications, and local ref tests   ###
    ################################################################################

    # add custom directory containing tests for locally referenced schema files
    localRefTestDirectoryName = basename(abspath(localReferenceTestsDirectory))
    @testset "Test suite for $draftfn" for draftfn in ["draft4", "draft6", localRefTestDirectoryName]
        tsdir = joinpath(jsonTestFilesDirectory, draftfn)

        # the test suites use the 'remotes' folder to simulate remote refs with the
        #  'http://localhost:1234' url.  To have tests cope with this, the id dictionary
        # is preloaded with the files in ''../remotes'
        idmap0 = Dict{String, Any}()
        remfn = joinpath(tsdir, "../../remotes")
        for rn in ["integer.json", "name.json", "subSchemas.json", "folder/folderInteger.json"]
            idmap0["http://localhost:1234/" * rn] = Schema(JSON.parsefile(joinpath(remfn, rn))).data
        end

        @testset "$tfn" for tfn in filter(n -> occursin(r"\.json$",n), readdir(tsdir))
            fn = joinpath(tsdir, tfn)
            schema = JSON.parsefile(fn)            
            @testset "- $(subschema["description"])" for subschema in (schema)
                spec = subschema["schema"] isa Bool ? 
                    Schema(subschema["schema"]; idmap0=idmap0) : 
                    Schema(subschema["schema"]; idmap0=idmap0, parentFileDirectory = dirname(fn))
                    
                @testset "* $(subtest["description"])" for subtest in subschema["tests"]
                    @test isvalid(subtest["data"], spec) == subtest["valid"]
                end
            end
        end
    end

end
