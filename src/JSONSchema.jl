module JSONSchema

using JSON
import HTTP

import Base: isvalid

export Schema, isvalid, diagnose

include("schema.jl")
include("validation.jl")

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
