module JSONSchema

using Compat
include("schema_parsing.jl")

fn = joinpath(@__DIR__, "enum.json")
schema = JSON.parsefile(fn)




















spec = Schema(schema[3]["schema"])
check(schema[3]["tests"][1]["data"], spec)
evaluate(schema[3]["tests"][1]["data"], spec)

using Base.Test
basename(fn)
files = ["enum.json"]
@testset "$a" for a in files
    fn = joinpath(@__DIR__, a)
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

check(schema[1]["tests"][1]["data"], spec)

refs = Dict{String, SpecDef}()
rootSpec = toDef(schema["definitions"]["TopLevelExtendedSpec"])

# length(refs) # 124
# dl = rootSpec.items[2].props["layer"]
# dl2 = dl.items.items[1]
# dl2 === dl2.props["layer"].items.items[1] # true, OK
# Base.summarysize(rootSpec) # 203k
# package code goes here

end # module
