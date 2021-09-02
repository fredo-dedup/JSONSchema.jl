module JSONSchema

using JSON
import HTTP
import URIs

export Schema, validate

include("schema.jl")
include("validation.jl")

export diagnose
function diagnose(x, schema)
    Base.depwarn(
        "`diagnose(x, schema)` is deprecated. Use `validate(schema, x)` instead.",
        :diagnose,
    )
    ret = validate(schema, x)
    return ret === nothing ? nothing : sprint(show, ret)
end

end
