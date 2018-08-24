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


####################################################################
# idmap setup for tests
####################################################################

idmap0 = Dict{String, Any}()
remfn = joinpath(tsdir, "../../remotes")
for rn in ["integer.json", "name.json", "subSchemas.json", "folder/folderInteger.json"]
    idmap0["http://localhost:1234/" * rn] = Schema(JSON.parsefile(joinpath(remfn, rn))).data
end

idmap0["http://json-schema.org:/draft-04/schema"] =
    Schema(JSON.parsefile("c:/temp/draft04-schema.json")).data;

idmap0["http://json-schema.org:/draft-06/schema"] =
    Schema(JSON.parsefile("c:/temp/draft06-schema.json")).data;

idmap0["http://json-schema.org:/draft-07/schema"] =
    Schema(JSON.parsefile("c:/temp/draft07-schema.json")).data;

####################################################################
# ref remotes problem
####################################################################

schema = JSON.parsefile(joinpath(tsdir, "refRemote.json"))
subschema = schema[7]
# clipboard(subschema["schema"])
# collect(keys(idmap0))

spec = Schema(subschema["schema"], idmap0=idmap0)
runsubtests(subschema, spec)

subtest = subschema["tests"][2]
res = JSONSchema.isvalid(subtest["data"], spec)
JSONSchema.validate(subtest["data"], spec)


schema = JSON.parsefile(joinpath(tsdir, "refRemote.json"))
schema = JSON.parsefile(joinpath(tsdir, "ref.json"))
for subschema in schema
    @info "⨀ $(subschema["description"])"
    spec = Schema(subschema["schema"], idmap0=idmap0)
    runsubtests(subschema, spec)
end

####################################################################
# ref.json errors

schema = JSON.parsefile(joinpath(tsdir, "ref.json"))
subschema = schema[10]

spec = Schema(subschema["schema"], idmap0=idmap0)
runsubtests(subschema, spec)

for subschema in schema
    @info "⨀ $(subschema["description"])"
    spec = Schema(subschema["schema"], idmap0=idmap0)
    runsubtests(subschema, spec)
end


#################################################################################
## diagnostic tuning
#################################################################################

sch = JSON.parsefile(joinpath(@__DIR__, "vega-lite-schema-3.0.0.json"))

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
        "x2": {"field": "a", "type": "ordinal"},
        "y": {"field": "b", "type": "quantitative"}
      }
    }

    """)

isvalid(jstest, sch2)
diagnose(jstest, sch2)
diagno = JSONSchema.validate(jstest, sch2)

error(report(jstest, sch2))


flatten(ofi::JSONSchema.OneOfIssue) = vcat([flatten(i) for i in ofi.issues]...)
flatten(si::JSONSchema.SingleIssue) = [si;]

singleissuerecap(si::JSONSchema.SingleIssue) =
    "in [$(join(si.path, '.'))] : $(si.msg)"

flatten(diagno)

function report(x, s::Schema)
    hyps = JSONSchema.validate(x, s)
    (hyps == nothing) && return nothing

    hyps2 = flatten(hyps)

    # The selection heuristic is to keep only the issues appearing deeper in
    # the tree. This will trim out the 'oneOf' assertions that were not
    # intended in the first place in 'x' (hopefully).
    lmax = maximum(e -> length(e.path), hyps2)
    filter!(e -> length(e.path) == lmax, hyps2)

    if length(hyps2) == 1
        return singleissuerecap(hyps2[1])
    else
        msg = ["One of :";
               map(x -> "  - " * singleissuerecap(x), hyps2) ]
        return join(msg, "\n")
    end
    nothing
end


function report(dat, sch)
  diag = JSONSchema.validate(dat, sch)

  if isa(diag, JSONSchema.OneOfIssue)
      lmax = maximum(e -> length(e.path), diag.issues)
      tmp = filter(e -> length(e.path) == lmax, diag.issues)
      diag = length(tmp)==1 ? tmp[1] : tmp
  end

  if isa(diag, JSONSchema.SingleIssue)
      error(singleissuerecap(diag))
  elseif isa(diag, Array)
      msg = ["One of :";
             map(x -> "  - " * singleissuerecap(x), diag)]
      error(join(msg, "\n"))
  end
  nothing
end



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






report(JSON.parse("{ \"foo\": true }"), myschema) # nothing
clipboard(report(JSON.parse("{ \"bar\": 12.5 }"), myschema))


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
