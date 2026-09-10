# Building and checks

Use Godot 4.7.1 and Python 3.11+. Run commands from the repository root. The application has been tested on Apple Silicon macOS with Metal and Forward+.

## Checks

After fetching the assets and importing the project:

```sh
godot --headless --path . --script res://qa/test_player.gd --fixed-fps 60 -- --qa
godot --headless --path . --script res://qa/world_physics.gd --fixed-fps 60 -- --qa
```

The controller suite checks input, pause behavior, stepping and camera interpolation. The world suite walks routes against the actual scene, including the shop entrance, main gate and landmark shortcuts. The current suites contain 39 and 35 checks respectively. World results are saved under Godot's `user://qa/` directory; the command prints the resolved path.

For rendered walking measurements:

```sh
mkdir -p .build/walking
godot --path . --resolution 1600x900 --script res://qa/moving_benchmark.gd -- --qa --qa-out="$PWD/.build/walking"
```

This walks three routes and records frame times and distance traveled. Performance depends on graphics settings and concurrent system load. Passing collision tests does not establish visual fidelity.

## Mac package

```sh
python3 tools/package_macos.py --version 0.1.0 --smoke-test
```

The packager finds `godot` on PATH, then the standard macOS application location. Set `GODOT` or pass `--godot` to choose another executable. It creates `.build/dist/Hidden Leaf.app`, bundles the engine and notices, ad hoc signs it and checks launch from an empty working directory. The build is for local Apple Silicon use and is not notarized.

## Geometry authoring

The published asset bundle is sufficient to run and package the application. Regenerating the scene additionally requires Blender 5.2:

```sh
blender --background --python tools/model/build_explorer.py
```

This replaces the generated village assets and writes an authoring scene under `.build/model/`. The original generation used macOS fonts for some lettering. On other systems, set `HIDDEN_LEAF_FONT` to a font with Japanese glyphs. Font choice can change the output.

Vegetation regeneration requires the original [Poly Haven tree_small_02](https://polyhaven.com/a/tree_small_02) Blender file and its texture dependencies, plus the fetched runtime textures:

```sh
blender --background --python tools/prepare_trees.py -- --source /path/to/tree_small_02.blend
```

The checked-in tools preserve the procedural authoring source. The release assets are the tested scene snapshot; regenerating them is a separate editing operation.
