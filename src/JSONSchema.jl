module JSONSchema

using JSON
using JSONPointer
import HTTP

export Schema, validate

include("schema.jl")
include("validation.jl")

export diagnose
function diagnose(x, schema)
    Base.depwarn(
        "`diagnose(x, schema)` is deprecated. Use `validate(x, schema)` instead.",
        :diagnose
    )
    ret = validate(x, schema)
    return ret === nothing ? nothing : sprint(show, ret)
end

end
