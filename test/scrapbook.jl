using JSONSchema
@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end



tsurl = "https://github.com/json-schema-org/JSON-Schema-Test-Suite/archive/master.zip"




using BinaryProvider

BinaryProvider.download(tsurl, prefix, verbose=true)

prefix = mktempdir()
prod = FileProduct(prefix, "JSON-Schema-Test-Suite-master/tests/draft4")

install(tsurl, "66656565", prefix=prefix, force=true, ignore_platform=true, verbose=true)


tsurl2 = "file://C:/Users/frtestar/Downloads/JSON-Schema-Test-Suite-master.zip"
install(tsurl2, "66656565", prefix=prefix, force=true, ignore_platform=true, verbose=true)


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


35.1 / 1.349


######## Source = https://github.com/json-schema-org/JSON-Schema-Test-Suite.git  #######

unzipdir = "c:/temp"
tsdir = joinpath(unzipdir, "JSON-Schema-Test-Suite-master/tests/draft4")
@testset "JSON schema test suite (draft 4)" begin
    @testset "$tfn" for tfn in filter(n -> ismatch(r"\.json$",n), readdir(tsdir))
        fn = joinpath(tsdir, tfn)
        schema = JSON.parsefile(fn)
        @testset "- $(subschema["description"])" for subschema in (schema)
            spec = Schema(subschema["schema"])
            @testset "* $(subtest["description"])" for subtest in subschema["tests"]
                @test check(subtest["data"], spec) == subtest["valid"]
            end
        end
    end
end


t = HTTP.URI("https://github.com/json-schema-org/JSON-Schema-Test-Suite.git")
fieldnames(t)
scheme(t)
methodswith(HTTP.URI)





HTTP.scheme(t)


HTTP.URI

HTTP.URIs..


#  MAP
fn = joinpath(tsdir, "oneOf.json")
schema = JSON.parsefile(fn)
subschema = schema[1]
spec = Schema(subschema["schema"])
for subtest in subschema["tests"]
    info("- ", subtest["description"],
         " : ", check(subtest["data"], spec),
         " / ", subtest["valid"])
end


tmpuri = "http://json-schema.org/draft-04/schema"
conf = (verbose=2,)

HTTP.get(tmpuri; verbose=2)
HTTP.request("GET", tmpuri)



ENV["https_proxy"] = ENV["http_proxy"]

spec0 = subschema["schema"]
mkSchema(subschema["schema"])
subtest = subschema["tests"][1]
x, s = subtest["data"], spec
check(x, s)
subtest["valid"]

typeof(s["properties"]["foo"])
s0 = spec
s = spec.asserts["items"][2]

asserts = copy(s.asserts)

macroexpand( quote @doassert asserts "not" begin
    check(x, keyval) && return "satisfies 'not' assertion $notassert"
end end)



#################################################################################


sch = JSON.parsefile(joinpath(@__DIR__, "vega-lite-schema.json"))
@time (sch2 = Schema(sch);nothing)

Profile.clear()
@profile (for i in 1:10 ; Schema(sch) ; end)
Profile.print()


jstest = JSON.parse("""
    {
      "\$schema": "https://vega.github.io/schema/vega-lite/v2.json",
      "description": "A simple bar chart with embedded data.",
      "data": {
        "values": [
          {"a": "A","b": 28}, {"a": "B","b": 55}, {"a": "C","b": 43},
          {"a": "D","b": 91}, {"a": "E","b": 81}, {"a": "F","b": 53},
          {"a": "G","b": 19}, {"a": "H","b": 87}, {"a": "I","b": 52}
        ]
      },
      "mark": "bar",
      "encoding": {
        "x3": {"field": "a", "type": "ordinal"},
        "y": {"field": "b", "type": "quantitative"}
      }
    }

    """)

@time validate(jstest, sch2);

ret = validate(jstest, sch2)










issue = ret.issues[1]
function shorterror(issue::SingleIssue)
    out  = (length(issue.path)==0) ? "" : "in `" * join(issue.path, ".") * "` : "
    out * issue.msg
end

function shorterror(issue::OneOfIssue)
    out = "one of these issues : \n"
    for is in issue.issues
        out *= " - " * shorterror(is) * "\n"
    end
    out
end

import Base: show

function show(io::IO, issue::OneOfIssue)
    out = "one of these issues : \n"
    for is in issue.issues
        out *= " - " * shorterror(is) * "\n"
    end
    println(IO, out)
end

show(ret)




ms = shorterror(ret)
println(ms)



Base.Markdown.MD("""
# aaa
 - _error_ here !


 """)


Profile.clear()
@profile evaluate(jstest, sch2)

Profile.print()

5+6
