# Production decisions

Preserve the original Git history and the Leaf authoring modules. Work on `five-villages` until the release gates pass.

The pipeline is evidence → metric village specification → shared construction helpers and village-specific geometry → imported, configured runtime scene → one active scene. Village switching uses threaded resource loading with explicit busy and failure states. The persistent player stays outside the disposable world root.

The current Leaf runtime builds 1,827 mesh instances and 2,676 trees at startup. Each tree creates six scene nodes. That representation needs measurement and restructuring before greater density is added. Asset count is not a quality metric.

Godot's [visibility-range documentation](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html) supports spatial HLOD with local culling and grouped distant geometry. Its [MultiMesh guidance](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) warns that individual instances cannot be culled independently within a batch. Use spatially bounded batches, retaining actual silhouettes and keeping near-field collision separate.

The cinematic reference is [Sucker Punch's scene-by-scene discussion of the E3 2018 reveal](https://blog.playstation.com/archive/2018/06/19/everything-you-need-to-know-about-that-incredible-ghost-of-tsushima-e3-trailer). The applicable direction is a readable environment reveal, continuity into player-scale movement, restrained interface and environment motion. Trailer capture must use the same scene assets and graphics preset as exploration. Shot planning is pending direct study of the footage and successful environment approval.

Release approval requires all five villages, evidence review, physical traversal, sustained frame-time and memory measurements, an isolated reproducible package, actual-runtime trailer exports, and verified public links. Partial infrastructure or passing source tests do not satisfy release approval.
