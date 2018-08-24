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

################################################################################
### Applying test suites for draft 4/6 specifications                        ###
################################################################################

@testset begin

    @testset "Test suite for $draftfn" for draftfn in ["draft4", "draft6"]
        tsdir = joinpath(unzipdir, "JSON-Schema-Test-Suite-master/tests", draftfn)

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
                spec = Schema(subschema["schema"], idmap0=idmap0)
                @testset "* $(subtest["description"])" for subtest in subschema["tests"]
                    @test isvalid(subtest["data"], spec) == subtest["valid"]
                end
            end
        end
    end

end
