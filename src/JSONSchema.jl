module JSONSchema

using JSON
import HTTP

export Schema, validate

include("schema.jl")
include("validation.jl")

export diagnose
function diagnose(x, schema)
    Base.depwarn(
        "`diagnose(x, schema)` is deprecated. Use `validate(x, schema; diagnose=true)` " *
        "instead.",
        :diagnose
    )
    validate(x, schema; diagnose = true)
    return
end

end
