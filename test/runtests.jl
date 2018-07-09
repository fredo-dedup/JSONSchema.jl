using JSONSchema
@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

### Load the JSON schema org test suite  ###
tsurl = "https://github.com/json-schema-org/JSON-Schema-Test-Suite/archive/master.zip"

using BinDeps
@BinDeps.setup

destdir = mktempdir()
dwnldfn = joinpath(destdir, "test-suite.zip")
unzipdir = joinpath(destdir, "test-suite")
run(@build_steps begin
    CreateDirectory(destdir, true)
    FileDownloader(tsurl, dwnldfn)
    CreateDirectory(unzipdir, true)
    FileUnpacker(dwnldfn, unzipdir, "JSON-Schema-Test-Suite-master/tests")
end)


### testing for draft 4 specifications  ###

tsdir = joinpath(unzipdir, "JSON-Schema-Test-Suite-master/tests/draft4")
@testset "JSON schema test suite (draft 4)" begin
    @testset "$tfn" for tfn in filter(n -> ismatch(r"\.json$",n), readdir(tsdir))
        fn = joinpath(tsdir, tfn)
        schema = JSON.parsefile(fn)
        @testset "- $(subschema["description"])" for subschema in (schema)
            spec = Schema(subschema["schema"])
            @testset "* $(subtest["description"])" for subtest in subschema["tests"]
                @test isvalid(subtest["data"], spec) == subtest["valid"]
            end
        end
    end
end
