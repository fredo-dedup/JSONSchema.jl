struct SuiteRetriever <: Resources.AbstractRetriever
    remotes::String
end

function Resources.retrieve(retriever::SuiteRetriever, id::Resources.ResourceId)
    uri = id.uri
    if lowercase(uri.host) == "localhost"
        relative = lstrip(Resources.URIs.unescapeuri(uri.path), '/')
        file = joinpath(retriever.remotes, relative)
        isfile(file) ||
            throw(Resources.RetrievalError(id, "suite remote does not exist"))
        return Resources.RetrievedResource(
            id,
            read(file);
            media_type = "application/schema+json",
        )
    end
    io = IOBuffer()
    response = Downloads.request(string(id); output = io, throw = false)
    if response isa Downloads.Response && response.status == 200
        return Resources.RetrievedResource(
            id,
            take!(seekstart(io));
            media_type = "application/schema+json",
        )
    end
    return throw(Resources.RetrievalError(id, "HTTP retrieval failed"))
end

@testset "Compiled schema resources" begin
    source = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "\$id" => "https://example.com/root",
        "\$defs" => Dict(
            "text" => Dict("\$anchor" => "text", "type" => "string"),
            "nested" => Dict(
                "\$id" => "nested",
                "type" => "object",
                "properties" => Dict("value" => Dict("\$ref" => "#value")),
                "\$defs" => Dict(
                    "value" => Dict(
                        "\$dynamicAnchor" => "value",
                        "type" => "integer",
                    ),
                ),
            ),
        ),
        "\$ref" => "#text",
        "minLength" => 2,
    )
    original = deepcopy(source)
    compiled = JSONSchema.CompiledSchema(source)
    @test source == original
    @test compiled.dialect === JSONSchema.DRAFT202012
    @test string(compiled.root.resource) == "https://example.com/root"
    @test haskey(
        compiled.registry,
        Resources.ResourceId("https://example.com/nested"),
    )
    @test isvalid(compiled, "ok")
    @test !isvalid(compiled, "x")
    @test !isvalid(compiled, 1)

    legacy = JSONSchema.CompiledSchema(
        Dict(
            "\$ref" => "#/definitions/text",
            "minLength" => 3,
            "definitions" => Dict("text" => Dict("type" => "string")),
        ),
    )
    @test isvalid(legacy, "x")
    @test !isvalid(legacy, 1)
end

@testset "Compiled schema retrieval policy" begin
    schema = Dict("\$ref" => "https://example.com/string")
    @test_throws JSONSchema.CompilationError JSONSchema.CompiledSchema(schema)
    retriever = Resources.MemoryRetriever(
        Dict("https://example.com/string" => "{\"type\":\"string\"}"),
    )
    compiled = JSONSchema.CompiledSchema(schema; retriever)
    @test isvalid(compiled, "text")
    @test !isvalid(compiled, 1)

    requested = Resources.ResourceId("https://example.com/redirect")
    final = Resources.ResourceId("https://cdn.example.com/string")
    redirected = Resources.MemoryRetriever(
        Dict(
            requested => Resources.RetrievedResource(
                final,
                Vector{UInt8}(codeunits("{\"type\":\"string\"}")),
            ),
        ),
    )
    redirected_schema = JSONSchema.CompiledSchema(
        Dict("\$ref" => string(requested));
        retriever = redirected,
    )
    @test isvalid(redirected_schema, "text")
end

@testset "Compiled schema bounds and diagnostics" begin
    @test_throws JSONSchema.CompilationError JSONSchema.CompiledSchema(
        Dict("type" => "string");
        max_nodes = 1,
    )
    nested =
        Dict("allOf" => Any[Dict("allOf" => Any[Dict("type" => "string")])])
    @test_throws JSONSchema.CompilationError JSONSchema.CompiledSchema(
        nested;
        max_depth = 2,
    )
    cyclic = Dict{String,Any}()
    cyclic["not"] = cyclic
    @test_throws JSONSchema.CompilationError JSONSchema.CompiledSchema(cyclic)

    compiled = JSONSchema.CompiledSchema(
        Dict(
            "\$schema" => JSONSchema.DRAFT202012.uri,
            "properties" => Dict("a/b" => Dict("type" => "integer")),
        ),
    )
    issue = JSONSchema.validate(compiled, Dict("a/b" => "wrong"))
    @test issue.path == "/a~1b"

    legacy_unknown = JSONSchema.CompiledSchema(
        Dict(
            "\$schema" => JSONSchema.DRAFT7.uri,
            "\$defs" => Dict(
                "not-a-schema" => Dict(
                    "\$id" => "https://example.com/not-a-resource",
                ),
            ),
        ),
    )
    @test !haskey(
        legacy_unknown.registry,
        Resources.ResourceId("https://example.com/not-a-resource"),
    )
end

@testset "Dialect keyword isolation" begin
    draft4_if = JSONSchema.CompiledSchema(
        Dict(
            "if" => Dict("\$ref" => "https://unregistered.example/schema"),
            "then" => Dict("type" => "string"),
        );
        dialect = JSONSchema.DRAFT4,
    )
    @test isvalid(draft4_if, 1)

    removed_dependency = JSONSchema.CompiledSchema(
        Dict("dependencies" => Dict("a" => ["b"]));
        dialect = JSONSchema.DRAFT202012,
    )
    @test isvalid(removed_dependency, Dict("a" => 1))

    modern_child = Dict(
        "\$schema" => JSONSchema.DRAFT7.uri,
        "\$id" => "https://example.com/modern-child",
        "type" => "string",
    )
    cross_dialect = JSONSchema.CompiledSchema(
        Dict(
            "id" => "https://example.com/legacy-root",
            "definitions" => Dict("child" => modern_child),
            "allOf" =>
                Any[Dict("\$ref" => "https://example.com/modern-child")],
        );
        dialect = JSONSchema.DRAFT4,
    )
    @test isvalid(cross_dialect, "text")
    @test !isvalid(cross_dialect, 1)

    for schema_dialect in (JSONSchema.DRAFT6, JSONSchema.DRAFT7)
        anchored = JSONSchema.CompiledSchema(
            Dict("\$id" => "#root-anchor", "type" => "integer");
            dialect = schema_dialect,
        )
        resolved = Resources.resolve(
            anchored.registry,
            Resources.Reference(anchored.root.resource, "#root-anchor"),
        )
        @test resolved.id == anchored.root
    end
end

@testset "Compiled evaluation safety" begin
    cycle = JSONSchema.CompiledSchema(
        Dict("\$ref" => "#");
        dialect = JSONSchema.DRAFT202012,
    )
    @test_throws JSONSchema.EvaluationError JSONSchema.validate(cycle, 42)

    nested = JSONSchema.CompiledSchema(
        Dict("items" => Dict("items" => Dict("type" => "integer")));
        dialect = JSONSchema.DRAFT202012,
    )
    @test_throws JSONSchema.EvaluationError JSONSchema.validate(
        nested,
        Any[Any[1]];
        max_evaluations = 2,
    )
    @test_throws JSONSchema.CompilationError JSONSchema.CompiledSchema(
        Dict("pattern" => "[");
        dialect = JSONSchema.DRAFT202012,
    )
    @test_throws JSONSchema.CompilationError JSONSchema.CompiledSchema(
        Dict("contains" => Dict(), "minContains" => "invalid");
        dialect = JSONSchema.DRAFT202012,
    )

    many_failures = JSONSchema.CompiledSchema(
        Dict("allOf" => Any[false for _ in 1:10]);
        dialect = JSONSchema.DRAFT202012,
    )
    @test JSONSchema.validate(many_failures, 1; max_issues = 1) !== nothing
    @test_throws JSONSchema.EvaluationError JSONSchema.validate(
        many_failures,
        1;
        fail_fast = false,
        max_issues = 1,
    )
    speculative = JSONSchema.CompiledSchema(
        Dict("anyOf" => Any[[false for _ in 1:10]; true]);
        dialect = JSONSchema.DRAFT202012,
    )
    @test isempty(
        JSONSchema.validate(speculative, 1; fail_fast = false, max_issues = 1),
    )

    short_circuit = JSONSchema.CompiledSchema(
        Dict(
            "\$schema" => JSONSchema.DRAFT202012.uri,
            "type" => "string",
            "allOf" => [Dict("\$ref" => "#")],
        ),
    )
    issue = JSONSchema.validate(short_circuit, 1)
    @test issue.reason == "type"
    @test_throws JSONSchema.EvaluationError JSONSchema.validate(
        short_circuit,
        1;
        fail_fast = false,
    )
end

@testset "Nested resource canonicalization" begin
    child = Dict(
        "\$id" => "sub/",
        "\$defs" => Dict("value" => Dict("\$ref" => "other")),
    )
    parent = Dict(
        "\$id" => "https://example.com/parent/",
        "\$defs" => Dict("child" => child),
    )
    schema = Dict(
        "\$schema" => JSONSchema.DRAFT202012.uri,
        "\$id" => "https://example.com/root",
        "\$defs" => Dict("parent" => parent),
        "\$ref" => "https://example.com/parent/#/\$defs/child/\$defs/value",
    )
    retriever = Resources.MemoryRetriever(
        Dict(
            "https://example.com/parent/sub/other" => "{\"type\":\"integer\"}",
        ),
    )
    compiled = JSONSchema.CompiledSchema(schema; retriever)
    @test isvalid(compiled, 1)
    @test !isvalid(compiled, "text")
end

@testset "Embedded schema resources" begin
    document_id = Resources.ResourceId("https://example.com/api.json")
    document = Resources.Resource(
        document_id,
        Dict(
            "components" => Dict(
                "schemas" => Dict(
                    "Root" => Dict("\$ref" => "#/components/schemas/Value"),
                    "Value" => Dict("type" => "string"),
                ),
            ),
        ),
    )
    compiled = JSONSchema.CompiledSchema(
        document,
        Resources.JSONPointer("/components/schemas/Root");
        dialect = JSONSchema.DRAFT202012,
    )
    @test isvalid(compiled, "text")
    @test !isvalid(compiled, 1)
    @test compiled.registry isa Resources.FrozenRegistry
    resources = compiled.registry.resources
    empty!(resources)
    dialects = compiled.dialects
    empty!(dialects)
    @test isvalid(compiled, "still immutable")

    self_id = Resources.ResourceId("https://example.com/self")
    self_resource = Resources.Resource(
        self_id,
        Dict("\$id" => string(self_id), "type" => "integer"),
    )
    self_compiled = JSONSchema.CompiledSchema(
        self_resource;
        dialect = JSONSchema.DRAFT202012,
    )
    @test self_compiled.root.resource == self_id
    @test isvalid(self_compiled, 1)

    declared_id = Resources.ResourceId("https://example.com/declared")
    declared_resource = Resources.Resource(
        Resources.ResourceId("https://example.com/retrieved"),
        Dict("\$id" => string(declared_id), "type" => "string"),
    )
    declared_compiled = JSONSchema.CompiledSchema(
        declared_resource;
        dialect = JSONSchema.DRAFT202012,
    )
    @test declared_compiled.root.resource == declared_id
    @test isvalid(declared_compiled, "text")

    nested_document_id =
        Resources.ResourceId("https://example.com/outer/root.json")
    nested_document = Resources.Resource(
        nested_document_id,
        Dict(
            "\$defs" => Dict(
                "inner" => Dict(
                    "\$id" => "inner/",
                    "\$defs" => Dict("leaf" => Dict("\$ref" => "other")),
                ),
            ),
        ),
    )
    nested_retriever = Resources.MemoryRetriever(
        Dict(
            "https://example.com/outer/inner/other" => "{\"type\":\"integer\"}",
            "https://example.com/outer/other" => "{\"type\":\"string\"}",
        ),
    )
    nested_compiled = JSONSchema.CompiledSchema(
        nested_document,
        Resources.JSONPointer("/\$defs/inner/\$defs/leaf");
        dialect = JSONSchema.DRAFT202012,
        retriever = nested_retriever,
    )
    @test isvalid(nested_compiled, 1)
    @test !isvalid(nested_compiled, "text")
end

@testset "Multiple embedded schema roots" begin
    document_id = Resources.ResourceId("https://example.com/api.json")
    document = Resources.Resource(
        document_id,
        Dict(
            "components" => Dict(
                "schemas" => Dict(
                    # Keep the referring schema first. Compilation must not
                    # depend on object or root order.
                    "Result" => Dict(
                        "\$id" => "result",
                        "type" => "object",
                        "properties" => Dict(
                            "value" => Dict("\$ref" => "value"),
                        ),
                        "required" => ["value"],
                    ),
                    "Value" => Dict(
                        "\$id" => "value",
                        "type" => "string",
                        "minLength" => 2,
                    ),
                    "Pointer" => Dict("\$ref" => "#/components/schemas/Value"),
                ),
            ),
        ),
    )
    result_pointer = Resources.JSONPointer("/components/schemas/Result")
    value_pointer = Resources.JSONPointer("/components/schemas/Value")
    pointer_pointer = Resources.JSONPointer("/components/schemas/Pointer")
    roots = [result_pointer, value_pointer, pointer_pointer]
    schemas = JSONSchema.CompiledSchemas(
        document,
        roots;
        dialect = JSONSchema.DRAFT202012,
    )

    result = JSONSchema.select(
        schemas,
        Resources.NodeId(document_id, result_pointer),
    )
    value = JSONSchema.select(schemas, document_id, value_pointer)
    pointer = JSONSchema.select(schemas, document_id, pointer_pointer)
    @test isvalid(result, Dict("value" => "ok"))
    @test !isvalid(result, Dict("value" => "x"))
    @test isvalid(value, "ok")
    @test !isvalid(value, 1)
    @test isvalid(pointer, "ok")
    @test !isvalid(pointer, 1)
    value_property = JSONSchema.subschema(
        schemas,
        Resources.ResourceId("https://example.com/result"),
        Resources.JSONPointer("/properties/value"),
    )
    @test isvalid(value_property, "ok")
    @test !isvalid(value_property, 1)

    roots_copy = schemas.roots
    empty!(roots_copy)
    @test isvalid(value, "still immutable")
    @test_throws ArgumentError JSONSchema.select(
        schemas,
        document_id,
        Resources.JSONPointer("/components/schemas/Missing"),
    )

    external_id = Resources.ResourceId("https://example.net/shared.json")
    external = Resources.Resource(
        external_id,
        Dict("schemas" => Dict("Count" => Dict("type" => "integer"))),
    )
    external_pointer = Resources.JSONPointer("/schemas/Count")
    combined = JSONSchema.CompiledSchemas(
        [document, external],
        [
            Resources.NodeId(document_id, value_pointer),
            Resources.NodeId(external_id, external_pointer),
        ];
        dialect = JSONSchema.DRAFT202012,
    )
    count = JSONSchema.select(combined, external_id, external_pointer)
    @test isvalid(count, 1)
    @test !isvalid(count, "one")

    dialect_document_id = Resources.ResourceId("https://example.org/mixed.json")
    legacy_pointer = Resources.JSONPointer("/schemas/Legacy")
    modern_pointer = Resources.JSONPointer("/schemas/Modern")
    dialect_document = Resources.Resource(
        dialect_document_id,
        Dict(
            "schemas" => Dict(
                "Legacy" => Dict(
                    "id" => "legacy",
                    "type" => "number",
                    "minimum" => 0,
                    "exclusiveMinimum" => true,
                ),
                "Modern" => Dict(
                    "\$id" => "modern",
                    "type" => "number",
                    "exclusiveMinimum" => 0,
                ),
            ),
        ),
    )
    legacy_node = Resources.NodeId(dialect_document_id, legacy_pointer)
    modern_node = Resources.NodeId(dialect_document_id, modern_pointer)
    mixed = JSONSchema.CompiledSchemas(
        [dialect_document],
        [legacy_node, modern_node];
        dialect = JSONSchema.DRAFT7,
        root_dialects = Dict(
            legacy_node => JSONSchema.DRAFT4,
            modern_node => JSONSchema.DRAFT202012,
        ),
    )
    legacy = JSONSchema.select(mixed, legacy_node)
    modern = JSONSchema.select(mixed, modern_node)
    @test legacy.dialect === JSONSchema.DRAFT4
    @test modern.dialect === JSONSchema.DRAFT202012
    @test !isvalid(legacy, 0)
    @test isvalid(legacy, 1)
    @test !isvalid(modern, 0)
    @test isvalid(modern, 1)

    @test_throws ArgumentError JSONSchema.CompiledSchemas(
        Resources.Resource[],
        Resources.NodeId[];
        dialect = JSONSchema.DRAFT202012,
    )
    @test_throws ArgumentError JSONSchema.CompiledSchemas(
        [document],
        Resources.NodeId[];
        dialect = JSONSchema.DRAFT202012,
    )
    @test_throws ArgumentError JSONSchema.CompiledSchemas(
        [document, external],
        [Resources.NodeId(document_id, value_pointer)];
        dialect = JSONSchema.DRAFT202012,
        max_resources = 1,
    )
end

@testset "Compiled evaluation performance and concurrency" begin
    schema = Dict{String,Any}("type" => "integer")
    instance = 1
    for _ in 1:60
        schema = Dict{String,Any}(
            "type" => "object",
            "properties" => Dict("value" => schema),
            "required" => ["value"],
        )
        instance = Dict{String,Any}("value" => instance)
    end
    compiled = JSONSchema.CompiledSchema(schema; dialect = JSONSchema.DRAFT7)
    legacy = JSONSchema.Schema(schema)
    @test isvalid(compiled, instance)
    @test all(
        fetch,
        [Threads.@spawn(isvalid(compiled, instance)) for _ in 1:32],
    )
    isvalid(compiled, instance)
    isvalid(legacy, instance)
    compiled_time = @elapsed for _ in 1:100
        isvalid(compiled, instance)
    end
    legacy_time = @elapsed for _ in 1:100
        isvalid(legacy, instance)
    end
    @test compiled_time < 10 * legacy_time
end

@testset "Compiler resource and vocabulary limits" begin
    definitions = Dict(
        "resource-$index" => Dict(
            "\$id" => "https://example.com/resource-$index",
            "type" => "integer",
        ) for index in 1:10
    )
    @test_throws JSONSchema.CompilationError JSONSchema.CompiledSchema(
        Dict("\$schema" => JSONSchema.DRAFT202012.uri, "\$defs" => definitions);
        max_resources = 5,
    )

    dialect_uri = "https://example.com/format-dialect"
    meta = JSON.json(
        Dict(
            "\$schema" => JSONSchema.DRAFT202012.uri,
            "\$id" => dialect_uri,
            "\$vocabulary" => Dict(
                "https://json-schema.org/draft/2020-12/vocab/core" => true,
                "https://json-schema.org/draft/2020-12/vocab/format-assertion" =>
                    true,
            ),
        ),
    )
    retriever = Resources.MemoryRetriever(Dict(dialect_uri => meta))
    @test_throws JSONSchema.CompilationError JSONSchema.CompiledSchema(
        Dict("\$schema" => dialect_uri);
        dialect = JSONSchema.DRAFT202012,
        retriever,
    )
end

function test_compiled_draft(dir::String, retriever, schema_dialect, base_uri)
    @testset "$(file)" for file in
                           filter(name -> endswith(name, ".json"), readdir(dir))
        file_path = joinpath(dir, file)
        @testset "$(group["description"])" for group in
                                               JSON.parsefile(file_path)
            compiled = JSONSchema.CompiledSchema(
                group["schema"];
                dialect = schema_dialect,
                base_uri,
                retriever,
            )
            @testset "$(case["description"])" for case in group["tests"]
                @test isvalid(compiled, case["data"]) == case["valid"]
                @test isempty(
                    JSONSchema.validate(
                        compiled,
                        case["data"];
                        fail_fast = false,
                    ),
                ) == case["valid"]
            end
        end
    end
    return
end

@testset "Compiled draft 2020-12" begin
    remotes = normpath(SCHEMA_TEST_DIR, "..", "remotes")
    retriever = SuiteRetriever(remotes)
    test_compiled_draft(
        joinpath(SCHEMA_TEST_DIR, "draft2020-12"),
        retriever,
        JSONSchema.DRAFT202012,
        "http://localhost:1234/draft2020-12/root",
    )
end

@testset "Compiled draft 2019-09" begin
    remotes = normpath(SCHEMA_TEST_DIR, "..", "remotes")
    retriever = SuiteRetriever(remotes)
    test_compiled_draft(
        joinpath(SCHEMA_TEST_DIR, "draft2019-09"),
        retriever,
        JSONSchema.DRAFT201909,
        "http://localhost:1234/draft2019-09/root",
    )
end

@testset "Compiled draft 7" begin
    remotes = normpath(SCHEMA_TEST_DIR, "..", "remotes")
    test_compiled_draft(
        joinpath(SCHEMA_TEST_DIR, "draft7"),
        SuiteRetriever(remotes),
        JSONSchema.DRAFT7,
        "http://localhost:1234/draft7/root",
    )
end
@testset "Compiled draft 6" begin
    remotes = normpath(SCHEMA_TEST_DIR, "..", "remotes")
    test_compiled_draft(
        joinpath(SCHEMA_TEST_DIR, "draft6"),
        SuiteRetriever(remotes),
        JSONSchema.DRAFT6,
        "http://localhost:1234/draft6/root",
    )
end
@testset "Compiled draft 4" begin
    remotes = normpath(SCHEMA_TEST_DIR, "..", "remotes")
    test_compiled_draft(
        joinpath(SCHEMA_TEST_DIR, "draft4"),
        SuiteRetriever(remotes),
        JSONSchema.DRAFT4,
        "http://localhost:1234/draft4/root",
    )
end
