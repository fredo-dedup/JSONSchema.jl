using JSONSchema, JSON

@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end


##### download test, issue =
### Exception calling "DownloadFile" with "2" argument(s): "The remote server returned an error: (407) Proxy
###     Authentication Required."
using BinaryProvider

src = "https://github.com/staticfloat/RmathBuilder/releases/download/v0.2.0-1/libRmath.x86_64-w64-mingw32.tar.gz"
dest = "C:/temp/libRmath.x86_64-w64-mingw32.tar.gz"

BinaryProvider.download(src, dest, verbose=true)


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



tsurl = "https://github.com/json-schema-org/JSON-Schema-Test-Suite/archive/master.zip"


BinaryProvider.gen_unpack_cmd(dwnldfn, unzipdir)
clipboard(BinaryProvider.gen_unpack_cmd(dwnldfn, unzipdir))


run(`'C:\HOMEWARE\julia\Julia-0.7.0\bin\7z.exe' x 'C:\Users\frtestar\AppData\Local\Temp\jl_94F.tmp\test-suite.zip' -y -so`, stdout=`'C:\HOMEWARE\julia\Julia-0.7.0\bin\7z.exe' x -si -y -ttar '-oC:\Users\frtestar\AppData\Local\Temp\jl_94F.tmp\test-suite'`)

mcm = pipeline(`'C:\HOMEWARE\julia\Julia-0.7.0\bin\7z.exe' x 'C:\Users\frtestar\AppData\Local\Temp\jl_94F.tmp\test-suite.zip' -y -so`, stdout=`'C:\HOMEWARE\julia\Julia-0.7.0\bin\7z.exe' x -si -y -ttar '-oC:\Users\frtestar\AppData\Local\Temp\jl_94F.tmp\test-suite'`)
run(mcm)

BinaryProvider.download(tsurl, prefix, verbose=true)

prefix = mktempdir()
prod = FileProduct(prefix, "JSON-Schema-Test-Suite-master/tests/draft4")

tsurl2 = "file://C:/Users/frtestar/Downloads/JSON-Schema-Test-Suite-master.zip"




##################################################################

using JSONSchema, JSON
import BinaryProvider

@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end


tsurl = "https://github.com/json-schema-org/JSON-Schema-Test-Suite/archive/1.2.0.tar.gz"

destdir = mktempdir()
dwnldfn = joinpath(destdir, "test-suite.tar.gz")
BinaryProvider.download(tsurl, dwnldfn, verbose=true)

unzipdir = joinpath(destdir, "test-suite")
BinaryProvider.unpack(dwnldfn, unzipdir)


### testing for draft 4 specifications  ###

tsdir = joinpath(unzipdir, "JSON-Schema-Test-Suite-1.2.0/tests/draft4")


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
                @test isvalid(subtest["data"], spec) == subtest["valid"]
            end
        end
    end
end



# ref remotes problem
fn = joinpath(tsdir, "refRemote.json")
schema = JSON.parsefile(fn)
subschema = schema[2]
spec = Schema(subschema["schema"])

import HTTP
specx = deepcopy(subschema["schema"])
# construct dictionary of 'id' properties to resolve references later
idmap = Dict{String, Any}()
id0 = HTTP.URI()
idmap[string(id0)] = specx
JSONSchema.mkidmap!(idmap, specx, id0)
idmap

v = "folder/"
uri = JSONSchema.toabsoluteURI(HTTP.URI("folderInteger.json"),
    HTTP.URI("http://localhost:1234/folder/"))



#  uri stripped of JPointer (aka 'fragment')
uri2 = rmfragment(uri) # without JPointer


JSONSchema.toabsoluteURI(HTTP.URI(v), id0)

JSONSchema.resolverefs!(specx, id0, idmap)

remfn = joinpath(tsdir, "../../remotes")
for rn in ["integer.json", "name.json", "subSchemas.json", "folder/folderInteger.json"]
    idmap["http://localhost:1234/" * rn] = Schema(JSON.parsefile(joinpath(remfn, rn))).data
end


# resolve all refs to the corresponding schema elements
JSONSchema.resolverefs!(specx, id0, idmap)

spec = Schema(specx)


idmap = Dict{String, Any}()
remfn = joinpath(tsdir, "../../remotes")
for rn in ["integer.json", "name.json", "subSchemas.json", "folder/folderInteger.json"]
    idmap["http://localhost:1234/" * rn] = Schema(JSON.parsefile(joinpath(remfn, rn))).data
end

#  MAP
fn = joinpath(tsdir, "refRemote.json")
schema = JSON.parsefile(fn)
subschema = schema[5]
spec = Schema(subschema["schema"], idmap=idmap)
for subtest in subschema["tests"]
    info("- ", subtest["description"],
         " : ", JSONSchema.isvalid(subtest["data"], spec),
         " / ", subtest["valid"])
end

ttt = JSONSchema.HTTP.URI(subschema["schema"]["\$ref"])
fieldnames(ttt)
clipboard(ttt)
ttt.scheme
uri = ttt
id0 = JSONSchema.HTTP.URI("")

JSONSchema.toabsoluteURI(uri, id0)

typeof(uri)

methods(JSONSchema.toabsoluteURI)



if uri.scheme == ""  # uri is relative to base uri => change just the path of id0
  uri = HTTP.URI(scheme   = id0.scheme,
                 userinfo = id0.userinfo,
                 host     = id0.host,
                 port     = id0.port,
                 query    = id0.query,
                 path     = "/" * uri.path)
end
uri




tmpuri = "http://json-schema.org/draft-04/schema"
conf = (verbose=2,)

HTTP.get(tmpuri; verbose=2)
HTTP.request("GET", tmpuri)





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

5+6
