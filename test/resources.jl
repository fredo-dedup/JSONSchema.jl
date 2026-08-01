const Resources = JSONSchema.Resources

@testset "JSON Pointer" begin
    pointer = Resources.JSONPointer("/a~1b/m~0n//0")
    @test collect(pointer) == ["a/b", "m~n", "", "0"]
    @test string(pointer) == "/a~1b/m~0n//0"
    @test string(Resources.JSONPointer() / "a/b" / "m~n") == "/a~1b/m~0n"
    @test isempty(Resources.JSONPointer(""))
    @test_throws Resources.PointerError Resources.JSONPointer("a")
    @test_throws Resources.PointerError Resources.JSONPointer("/~")
    @test_throws Resources.PointerError Resources.JSONPointer("/~2")

    document = Dict(
        "a/b" => Dict("m~n" => 1),
        "array" => Any["zero", Dict("" => "empty")],
    )
    @test Resources.resolve(document, Resources.JSONPointer("/a~1b/m~0n")) == 1
    @test Resources.resolve(document, Resources.JSONPointer("/array/0")) == "zero"
    @test Resources.resolve(document, Resources.JSONPointer("/array/1/")) == "empty"
    @test collect(Resources.JSONPointer("/")) == [""]
    @test_throws Resources.PointerError Resources.resolve(document, Resources.JSONPointer("/array/01"))
    @test_throws Resources.PointerError Resources.resolve(document, Resources.JSONPointer("/array/-"))
    @test_throws Resources.PointerError Resources.resolve(document, Resources.JSONPointer("/array/2"))
    @test_throws Resources.PointerError Resources.resolve(document, Resources.JSONPointer("/missing"))
end

@testset "Frozen JSON values" begin
    source = Dict("object" => Dict("value" => 1), "array" => Any[true, nothing])
    frozen = Resources.freeze(source)
    source["object"]["value"] = 2
    push!(source["array"], false)
    @test frozen isa Resources.FrozenObject
    @test frozen["object"] isa Resources.FrozenObject
    @test frozen["array"] isa Resources.FrozenArray
    @test frozen["object"]["value"] == 1
    @test frozen["array"] == Any[true, nothing]
    @test_throws MethodError setindex!(frozen, 2, "object")
    @test_throws Base.CanonicalIndexError setindex!(frozen["array"], false, 1)
    @test Resources.freeze(frozen) === frozen
    @test_throws ArgumentError Resources.freeze(Dict(1 => "invalid"))
end

@testset "Resource identifiers and references" begin
    id = Resources.ResourceId("HTTPS://EXAMPLE.COM:443/schemas/root.json")
    @test string(id) == "https://example.com/schemas/root.json"
    @test_throws ArgumentError Resources.ResourceId("https://example.com/root#part")

    reference = Resources.Reference(id, "../common.json#/a%20b/~0value")
    @test string(reference.resource) == "https://example.com/common.json"
    @test reference.fragment isa Resources.PointerFragment
    @test collect(reference.fragment.pointer) == ["a b", "~value"]

    anchor = Resources.Reference(id, "#named%2Danchor")
    @test anchor.fragment == Resources.AnchorFragment("named-anchor")
    @test Resources.Reference(id, "#").fragment isa Resources.RootFragment
end

@testset "Resource registry" begin
    retrieval = Resources.ResourceId("file:///tmp/schema.json")
    canonical = Resources.ResourceId("https://example.com/schema")
    document = Dict("defs" => Dict("thing" => Dict("type" => "string")))
    item_pointer = Resources.JSONPointer("/defs/thing")
    item = Resources.Resource(
        canonical,
        document;
        retrieval,
        media_type = "application/schema+json",
    )
    registry = Resources.Registry()
    Resources.register!(registry, item; anchors = ["thing" => item_pointer])

    by_pointer = Resources.resolve(
        registry,
        Resources.Reference(retrieval, "#/defs/thing"),
    )
    @test by_pointer.id == Resources.NodeId(canonical, item_pointer)
    @test by_pointer.value["type"] == "string"

    by_anchor = Resources.resolve(registry, Resources.Reference(canonical, "#thing"))
    @test by_anchor.id == by_pointer.id
    @test by_anchor.value === by_pointer.value
    @test_throws Resources.MissingAnchorError Resources.resolve(
        registry,
        Resources.Reference(canonical, "#missing"),
    )
    @test_throws Resources.MissingResourceError Resources.resource(
        registry,
        Resources.ResourceId("https://example.com/missing"),
    )
    @test_throws Resources.DuplicateResourceError Resources.register!(registry, item)

    invalid_registry = Resources.Registry()
    @test_throws Resources.PointerError Resources.register!(
        invalid_registry,
        item;
        anchors = ["invalid" => Resources.JSONPointer("/missing")],
    )
    @test isempty(invalid_registry.resources)
    @test isempty(invalid_registry.aliases)
    @test isempty(invalid_registry.anchors)
end
