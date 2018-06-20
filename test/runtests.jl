using JSONSchema
@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end



tsurl = "https://github.com/json-schema-org/JSON-Schema-Test-Suite/archive/master.zip"
destpath =  joinpath(@__DIR__, "../deps/test-suite")

mkpath(destpath)
download(tsurl, joinpath(@__DIR__, "../deps"))
fp = download(tsurl)


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

######## Source = https://github.com/json-schema-org/JSON-Schema-Test-Suite.git  #######

tsdir = joinpath(unzipdir, "JSON-Schema-Test-Suite-master/tests/draft6")
files = readdir(joinpath(unzipdir, "JSON-Schema-Test-Suite-master/tests/draft6"))

tfn = first(readdir(tsdir))

# ["enum.json"]
@testset "$tfn" for tfn in readdir(tsdir)
    fn = joinpath(tsdir, tfn)
    schema = JSON.parsefile(fn)
    for subtest in schema
        info(subtest["description"])
        spec = Schema(subtest["schema"])
        for t in subtest["tests"]
            info("- " * t["description"])
            @test check(t["data"], spec) == t["valid"]
        end
    end
end
