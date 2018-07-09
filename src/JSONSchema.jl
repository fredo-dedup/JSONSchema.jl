module JSONSchema

# using Compat
using JSON
import HTTP

import Base: isvalid

export Schema, isvalid, diagnose

include("schema.jl")
include("validation.jl")

end # module
