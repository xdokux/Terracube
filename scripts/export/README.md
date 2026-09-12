# CubyzReforged

Cubyz 0.3.0 with **irisbridge**: Minecraft OptiFine/Iris shaderpacks running natively inside
Cubyz.

The engine is [Cubyz](https://github.com/PixelGuys/Cubyz), a voxel game written in Zig. The
bridge is `mods/irisbridge/`. It reads a shaderpack in the OptiFine/Iris format, compiles the
pack's own GLSL against Cubyz's renderer through a generated prologue, and runs the pack's
shadow, gbuffers, deferred, composite and final passes in the order Iris runs them. Packs are
not rewritten by hand. The four things Cubyz does differently from Minecraft (no vertex
attributes, a Z-up world, a texture array instead of an atlas, and no G-buffer or shadow map of
its own) are each bridged once, in `mods/irisbridge/lib/`.

## Requirements

- Windows or Linux with a GPU that supports OpenGL 4.3.
- Zig **0.16.0** exactly (the version in `.zigversion`). The launch scripts fetch it for you.

## Build and run

**Windows, no tools needed:** run `run_windows.bat`. It downloads the matching Zig into
`compiler/`, builds a release build and starts the game. Afterwards `play_windows.bat` starts
the built game without rebuilding.

**With your own Zig 0.16.0:**

```
zig build -Doptimize=ReleaseFast
zig-out\bin\Cubyz.exe
```

Run the game from this folder; it looks for `assets/` relative to the working directory.

**Linux:** `./run_linux.sh`. The scripts are stored executable; if your extractor dropped
that, restore it once with `chmod +x *.sh scripts/*.sh`.

The first build downloads Cubyz's own dependencies (Cubyz-Libs, fonts, music). Nothing else
is fetched.

## Shaderpacks

1. Put a pack into `shaderpacks/`, as the `.zip` you downloaded or as a folder.
2. In game, open **Settings -> Shaders** and pick it. "None" returns to Cubyz's own rendering.
   Packs dropped into the folder while the game runs show up when the screen is reopened.
3. A pack's own options are under **Settings -> Shaders -> Pack options...**. The same values
   live in `shaderpacks/<pack>.options.txt`, created on first load; every line is commented out
   until you change one.

Packs this was developed against, all Iris 1.7-era releases:

| pack | state |
|---|---|
| Bliss v2.1.2 | loads and renders |
| BSL v10.1.3 | loads and renders |
| Complementary Unbound r5.8.1 | loads and renders; keep `ANISOTROPIC_FILTER` at 0 |
| Kappa v5.3 | loads and renders |
| Mellow Shader v3.4 | loads and renders; the newest addition, still being checked |
| Nostalgia v5.1 | loads and renders |
| photon v1.3b | loads and renders |
| Solas Shader V3.7b | loads and renders |
| Nostalgic Red Voxels V3, Rethinking Voxels | load; their voxel pipelines (custom images, buffer objects and compute programs) run and are the newest code here |

Custom images, shader storage buffers and compute programs are implemented as of 2026-09-11;
a pack's buffer objects are bound at binding point `16 + N` rather than `N`, because Cubyz's own
chunk shaders occupy the low points, and the pack's GLSL is rewritten to match. Cubyz's glass is
named for packs as Minecraft's `glass` and `<dye>_stained_glass` and given a stained-glass texel
built from its absorption map, since its own albedo is fully transparent; and translucent blocks
cast shadows, water and glass included, with `shadowtex1` the copy taken before them. The sun and
moon are drawn through `gbuffers_skytextured` over generated sheets, `at_midBlock.w` carries the
block's light level, eight shadow colour buffers exist and are allocated as used, and the
`alphaTest.`, `customTexture.` and `scale.` directives and the program fallback chain are honoured
as Iris does them. Not implemented:
the entity, hand, weather and armour-glint programs, `shadowcolor2` to `7`, and the Distant
Horizons extensions. Cubyz has no weather, status effects or held-item light, so the uniforms for
those read as constants. `docs/irisbridge-notes.md` lists every known limit with its reason.

## Layout

```
build.zig, build.zig.zon    the build; the bridge's engine hooks are generated from a list in build.zig
src/                        the Cubyz engine, with the bridge's hooks in src/renderer.zig
assets/                     Cubyz's assets
mods/irisbridge/lib/        the bridge: pack loading, the GLSL transformer, the vertex prologue,
                            render targets, uniforms, the expression language, the block map
mods/irisbridge/test/       the multi-pack conformance harness
mods/irisbridge/tests.zig   the bridge's unit tests, run by `zig build test`
shaderpacks/                where packs go
docs/                       the bridge's design notes and problem record, and the upstream Cubyz README
scripts/                    the Zig installer used by the launch scripts, and this export script
```

The files a build produces (`zig-out/`, `.zig-cache/`, `compiler/`) and the ones the game
writes (`logs/`, `saves/`, `settings.zig.zon`) are not part of the source.

## Tests

`zig build test` runs the bridge's unit tests together with the engine's. The bridge's tests
cover the GLSL transformer, the pack and properties parsers, the render-target flip sequence,
the coordinate bridge, the expression language, the shadow camera and the day cycle; none of
them needs a GPU.

The conformance harness transforms every program of every pack in `shaderpacks/` without a GPU
and reports what it could not handle. From the repository root, with `zig` on the PATH:

```
printf 'test {\n\t_ = @import("test/real_pack.zig");\n}\n' > mods/irisbridge/conformance_tmp.zig
zig test --dep main --dep pack --dep install -Mroot=mods/irisbridge/conformance_tmp.zig --dep main -Mpack=mods/irisbridge/lib/pack.zig --dep main -Minstall=mods/irisbridge/lib/install.zig --dep vec -Mmain=mods/irisbridge/test/main_stub.zig -Mvec=src/vec.zig
rm mods/irisbridge/conformance_tmp.zig
```

## Notes and credits

- `docs/irisbridge-notes.md` explains the design and records every problem found while making
  the packs above render, with its cause and fix. Read it before changing the bridge.
- `docs/cubyz-README.md` is the upstream Cubyz README.
- Cubyz is licensed as described in `LICENSE`. Shaderpacks belong to their authors and are not
  included; the Iris source was used as the reference for the format.
