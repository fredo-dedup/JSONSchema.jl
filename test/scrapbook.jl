using JSONSchema, JSON
using Test

##### download test, issue =


agent = "Bibi"
psh_path = "powershell"
webclient_code = """
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    \$webclient = (New-Object System.Net.Webclient);
    \$webclient.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials
    \$webclient.Headers.Add("user-agent", "$agent");
    \$webclient.DownloadFile("$src", "$dest")
    """

replace(webclient_code, "\n" => " ")
run(`$psh_path -NoProfile -Command "$webclient_code"`)

##################################################################
######## Source = https://github.com/json-schema-org/JSON-Schema-Test-Suite.git  #######

unzipdir = "c:/temp"
tsdir = joinpath(unzipdir, "JSON-Schema-Test-Suite-master/tests/draft4")
@testset "JSON schema test suite (draft 4)" begin
    @testset "$tfn" for tfn in filter(n -> occursin(r"\.json$",n), readdir(tsdir))
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

#################################################################

function runsubtests(subschema, spec)
    for subtest in subschema["tests"]
        res = JSONSchema.isvalid(subtest["data"], spec)
        expected = subtest["valid"]
        @info "$(subtest["description"]) : $res / $expected"
    end
end

#################################################################



#  MAP
schema = JSON.parsefile(joinpath(tsdir, "definitions.json"))
subschema = schema[1]
clipboard(subschema["schema"])
# "\$ref"=>"http://json-schema.org/draft-04/schema#"
spec = Schema(subschema["schema"])
for subtest in subschema["tests"]
    info("- ", subtest["description"],
         " : ", JSONSchema.isvalid(subtest["data"], spec),
         " / ", subtest["valid"])
end


# pb de proxy avec HTTP ???

using HTTP
io = Base.BufferStream()
@async while !eof(io)
    bytes = readavailable(io)
    println("GET data: \$bytes")
end
r = HTTP.request("GET", "http://httpbin.org/get", response_stream=io)
close(io)


####################################################################
# ref remotes problem

idmap0 = Dict{String, Any}()
remfn = joinpath(tsdir, "../../remotes")
for rn in ["integer.json", "name.json", "subSchemas.json", "folder/folderInteger.json"]
    idmap0["http://localhost:1234/" * rn] = Schema(JSON.parsefile(joinpath(remfn, rn))).data
end

schema = JSON.parsefile(joinpath(tsdir, "refRemote.json"))
subschema = schema[6]
# clipboard(subschema["schema"])

spec = Schema(subschema["schema"], idmap0=idmap0)
runsubtests(subschema, spec)

uri = HTTP.URI("folderInteger.json")
id0 = HTTP.URI("http://localhost:1234/folder")

uri = HTTP.URI(scheme   = id0.scheme,
           userinfo = id0.userinfo,
           host     = id0.host,
           port     = id0.port,
           query    = id0.query,
           path     = "/" * strip(id0.path, '/') * "/" * strip(uri.path, '/'))

methods(HTTP.URI)



for subschema in schema
    @info "⨀ $(subschema["description"])"
    spec = Schema(subschema["schema"], idmap0=idmap0)
    runsubtests(subschema, spec)
end






tmpuri = "http://json-schema.org/draft-04/schema"
conf = (verbose=2,)

HTTP.get(tmpuri; verbose=2)
HTTP.request("GET", tmpuri)





#################################################################################
## diagnostic tuning
#################################################################################

using JSONSchema
sch = JSON.parsefile(joinpath(@__DIR__, "vega-lite-schema.json"))

@time (sch2 = Schema(sch);nothing)

sch2 = Schema(sch)


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

isvalid(jstest, sch2)



myschema = Schema("""
 {
    "properties": {
       "foo": {},
       "bar": {}
    },
    "required": ["foo"]
 }""")


isvalid(JSON.parse("{ \"foo\": true }"), myschema) # true
isvalid(JSON.parse("{ \"bar\": 12.5 }"), myschema) # false

myschema["properties"]






diagnose("{ "foo": true }", myschema) # nothing
diagnose("{ "bar": 12.5 }", myschema)


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
