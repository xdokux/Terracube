# irisbridge — OptiFine/Iris shaderpack support for Cubyz

Runs Minecraft shaderpacks (the OptiFine format that Iris consumes) inside Cubyz.

## What this is, precisely

This is **not** Iris running inside Cubyz. Iris is Java bound to `net.minecraft.*`, Fabric and
Mojang's `GameRenderer`; none of that can execute in a Zig/OpenGL process. This is a native
reimplementation of the *shaderpack format and pipeline contract* that Iris implements, targeting
Cubyz's renderer.

The practical consequence: packs are loaded and executed as real programs, not emulated or
approximated at the effect level. A pack's own `composite1.fsh` runs, its own `gbuffers_terrain.vsh`
runs. But packs are written against Minecraft's specific vertex/G-buffer/lighting contract, and
Cubyz's differs in four fundamental ways. Each is bridged rather than papered over — see below.

Compatibility ceiling is "most packs render, many render correctly", not "every pack, pixel-identical".
Iris is ~100k lines of Java and still carries per-pack quirks *on Minecraft itself*; a port to a
different engine cannot do better.

## The four hard problems and how each is bridged

### 1. Cubyz terrain geometry has no vertex attributes

`assets/cubyz/shaders/chunks/chunk_vertex.vert` pulls everything from SSBOs indexed by
`gl_VertexID`/`gl_BaseInstance` — face data, quad corners, per-vertex light, chunk transforms. There
is no `gl_Vertex`, no `gl_MultiTexCoord0`, no vertex buffer at all.

Pack shaders are GLSL 120 *compatibility profile* and are built entirely on those built-ins, plus
Minecraft's `mc_Entity`, `mc_midTexCoord` and `at_tangent`.

**Bridge:** source injection. `lib/prologue.zig` generates a Cubyz-specific vertex prologue that
performs the SSBO pull exactly as `chunk_vertex.vert` does, then *synthesises* the Minecraft input
set from it — `cubyz_Vertex`, `cubyz_Normal`, `cubyz_Color`, `mc_Entity`, `mc_midTexCoord`,
`at_tangent`, `lmcoord`. The transformed pack source is spliced in after that prologue and sees a
complete, conventional Minecraft vertex environment.

The rename is not stylistic: GLSL reserves the `gl_` prefix, so `gl_Vertex` cannot be redeclared even
though core 460 does not define it. Every `gl_*` compat built-in is rewritten to a `cubyz_*` name
that the prologue declares. This is the same technique Iris uses (via glsl-transformer); here it is
done with a GLSL tokenizer in `lib/glsl.zig` rather than a full ANTLR parse.

### 2. Cubyz is Z-up; every pack hardcodes Y-up

Packs assume `upPosition` is +Y, sample sky gradients by `.y`, and build `shadowLightPosition` in
Y-up world space.

**Bridge:** a basis change folded into `gbufferModelView`, applied to every world-space uniform and
to the prologue's position output. The pack is handed a consistent Y-up world and never learns
otherwise. Exact rather than approximate — a change of basis, not a fudge.

**It is not only the world that differs, and this cost real debugging time.** Cubyz's *eye* space
is Z-up too: its projection matrix maps view Z to clip Y and uses view Y as the W divide. An
earlier version of this file claimed "view space needs no correction because Cubyz's eye space is
already the GL convention" — that was wrong. So `gbufferModelView` is the similarity transform
`B·V·B⁻¹`, and `gbufferProjection` is a genuine GL perspective matrix rebuilt from Cubyz's
(`matrix.glProjection`), not Cubyz's own.

Handing over Cubyz's projection matrix directly *almost* works, which is what makes it dangerous:
anything that multiplies by the whole matrix behaves, and only code reading individual entries
breaks. Nostalgia's fast path is

    pos = pos.xyzz * diag4(gl_ProjectionMatrix) + vec4(0.0, 0.0, gl_ProjectionMatrix[3].z, 0.0)

which reads the diagonal — all zeros in Cubyz's layout — so every vertex collapsed to the origin
with no GL error and no compile failure. The test now asserts equality of **clip** coordinates
rather than view coordinates, which is the property that actually matters.

### 3. Cubyz block textures are a `sampler2DArray`, not a stitched atlas

Packs call `texture2D(gtexture, texcoord)` against one big atlas, and POM/parallax walks neighbouring
texels within it.

**Bridge (implemented):** sampling calls are rewritten *by first argument*. Any
`texture`/`texture2D`/`textureLod` call whose first argument names the block texture becomes
`cubyz_sampleArray(...)`, which resolves the array layer from Cubyz's animated-texture index exactly
as `chunk_fragment.frag` does. Renaming the sampler alone cannot work — packs pass a two-component
coordinate, and there is no `texture(sampler2DArray, vec2)` overload whatever the sampler is called.
Rewriting by argument is also what keeps `lightmap` and `depthtex0` — genuinely 2D, in the very same
program — untouched.

`mc_midTexCoord` becomes the tile centre `(0.5, 0.5)` in layer space. Parallax then wraps within a
layer, which is *better behaved* than atlas POM: there are no neighbouring tiles to bleed in from.

**LabPBR material data (done for `specular`).** Cubyz has no LabPBR textures, but it does carry two
of the three things one encodes: per-texel reflectivity and per-texel emission. `specular` is
redirected to `cubyz_sampleSpecular`, which reads Cubyz's arrays at the same animated layer and
packs a LabPBR value:

- **Smoothness and F0 both come from reflectivity**, because that is precisely how
  `chunk_fragment.frag` reads it — `reflectivity * fixedCubeMapLookup(reflect(…))` is a
  perfect-mirror sample scaled by reflectivity, so the engine already treats a reflective block as a
  smooth one. Leaving smoothness at 0 would make every surface fully rough and suppress the very
  reflection the value was authored to produce. F0 is held below the 230/255 metal threshold: Cubyz
  has no metalness, and crossing into the metal range makes a pack tint reflections by the albedo
  and drop diffuse entirely.
- **Emission** uses Cubyz's own factor. `chunk_fragment.frag` compares `emission.r*4` against the
  light value, so 0.25 already means fully lit, and the same factor here makes a block glow in the
  pack at the strength it glows in the engine. Capped just below LabPBR's 255 "no emission"
  sentinel.
- **Porosity/SSS is left at 0.** Cubyz's absorption is a translucency tint, not either of those, so
  it stays unmapped rather than being forced into a channel that means something else.

This forced one generalisation in the transformer: `arraySamplers` became a list of *per-sampler*
redirects rather than one shared helper, because the targets are not interchangeable — the block
texture is a genuine array lookup, while `specular` is synthesised.

**`normals` is deliberately still a neutral 1×1 constant.** Cubyz has no normal, height or AO data
at any resolution, so `(0.5, 0.5, 1.0, 1.0)` — zero tangent-space perturbation, no occlusion, no
displacement — is already the correct answer. A helper could only return the same constant less
directly, and inventing a normal map from the albedo would be exactly the kind of fabrication this
port avoids elsewhere.

### 4. Cubyz has no G-buffer, no shadow map, and a different lighting model

`deferred_render_pass.frag` reads only colour, depth and bloom. There are no normals, no material
IDs, no shadow map anywhere in the engine (grepping `shadow` in `src/` finds only UI text shadows).
Lighting is per-vertex RGB sun + RGB block light unpacked from a `lightData` SSBO — not Minecraft's
2D lightmap sampled through `gl_MultiTexCoord1`.

**Bridge:** this is the part that is genuine engine work rather than translation, and it is the
least finished.

- *Done:* rather than emulating the gbuffers output contract, Cubyz's terrain draw is routed
  through the pack's **own** `gbuffers_terrain`, which writes whatever its `DRAWBUFFERS` directive
  names. `chunk_meshing.terrainOverride` swaps only the program, leaving Cubyz's raster state
  intact. That sidesteps having to guess a pack-specific colortex layout.
- *Done:* Cubyz's RGB sun/block light is collapsed to Minecraft's two lightmap scalars in the
  prologue. Genuinely lossy — Cubyz carries per-channel colour where Minecraft has two numbers —
  but lossy in the direction that matters least, since it already applied that colour to the light
  it stores.
- *Done:* a shadow pass. The pack's `shadow` program runs over the same chunk geometry through the
  same prologue, from the light's viewpoint — see "The shadow pass" below.
- *Done:* translucent chunks draw through the pack's `gbuffers_water`, with its own per-attachment
  blend state — see "Water and per-attachment blending" below.
- *Not done:* entities, particles and sky still draw through Cubyz's own shaders, so they land in
  the pack's colortex0 with Cubyz shading and contribute nothing to the material buffers.

## Layout

    lib/glsl.zig       GLSL tokenizer + compat-to-core transformer
    lib/pack.zig       pack discovery, shaders.properties, #include resolution, const parsing
    lib/preprocess.zig the #if/#else layer .properties files are read through (no GL)
    lib/flip.zig       colortex ping-pong resolution (no GL dependency, so it is testable)
    lib/blend.zig      blend.<program>[.colortexN] parsing and colortex-to-slot mapping (no GL)
    lib/blockmap.zig   block.properties, and how Cubyz block names match Minecraft ones (no GL)
    lib/blockids.zig   the GPU table that gives mc_Entity its value
    lib/targets.zig    colortex0-15 with per-target formats, depthtex0/1/2, shadow textures
    lib/matrix.zig     Z-up/Y-up basis change, 4x4 inverse, celestial positions
    lib/smoothing.zig  frame-rate-independent exponential smoothing (no GL, so it is testable)
    lib/uniforms.zig   the Iris uniform set, sourced from Cubyz state, Y-up corrected
    lib/options.zig    pack options: discovery, profiles, screens, override application
    lib/prologue.zig   the injected SSBO-pull vertex prologue described above
    lib/pipeline.zig   program compilation, standard macros, pass-graph execution
    lib/bridge.zig     module entry point; the only thing the engine imports

    tests.zig          collects every unit test into one module for `zig build test`
    test/run.bat       drives one `zig test` per file, for iterating without linking the engine
    test/main_stub.zig stand-in for Cubyz's `main`, forwarding `vec` to the real src/vec.zig

## Engine changes

All additive, following the pattern the terrain diffusion port established:
- `build.zig` generates `mods/renderhook.zig`, which re-exports `irisbridge` if present and
  provides no-op stubs otherwise, so the engine builds with or without this mod installed.
- `src/renderer.zig` gains five hook calls around world rendering, and `worldFrameBuffer` becomes
  public so the pipeline can read the lit world.
- `src/renderer/chunk_meshing.zig` gains `terrainOverride`, which swaps the terrain *program* while
  leaving Cubyz's raster state and buffers alone, and `transparentOverride`, which does the same for
  the translucent pass — that one also has to replace the blend state, for the reason in "Water and
  per-attachment blending".
- `src/main.zig`'s `c` import becomes public, since mod modules are given `main` and nothing else.
- `src/settings.zig` gains `shaderPack`.
- `src/renderer.zig` gains `ShaderPackOption`, the type the options screen and the mod agree on.
- `src/gui/windows/shader_options.zig` is the pack's own options screen, reached from `shaders.zig`.
- `src/blocks.zig` gains `typeCount()`, so the `mc_Entity` table can walk the block registry.
- `build.zig` gains a second test artifact, so `zig build test` runs this mod's tests too.

## Reference material in this tree

`../../../Iris/` holds the Iris source, and it is the authority for anything ambiguous — the
uniform list, program names, fallback rules, directive syntax. Prefer reading it over
reconstructing the spec from memory; two bugs below were found exactly that way.

`../../shaderpacks/` holds packs for testing, as `.zip` archives extracted on first load into
`.cache/`. Nostalgia v5.1 is the current fixture, at `profile = Ultra`.

## Status

- [x] GLSL transformer — `lib/glsl.zig`, 12 unit tests
- [x] Pack loading — `lib/pack.zig`, 9 unit tests
- [x] Render targets — `lib/targets.zig`, ping-pong logic in `lib/flip.zig`, 5 unit tests
- [x] Module wired into the engine build — `mods/renderhook.zig`, generated by `build.zig`
- [x] Coordinate bridge and matrix maths — `lib/matrix.zig`, 11 unit tests
- [x] Uniform set — `lib/uniforms.zig`, sourced from Cubyz state
- [x] Pass graph execution — `lib/pipeline.zig`, wired into `src/renderer.zig`
- [x] Vertex-pull prologue — `lib/prologue.zig`; the pack's `gbuffers_terrain` compiles and links
      against it on hardware
- [x] Cubyz's terrain draw routed through the pack's gbuffers program
- [x] Custom uniforms from `shaders.properties` — `lib/expression.zig` + `lib/customuniforms.zig`,
      25 unit tests
- [x] `.zip` packs, pack discovery, multi-pack conformance harness — `lib/install.zig`
- [x] Shadow pass — the pack's `shadow` program over Cubyz geometry from the light's viewpoint
- [x] Shadow sampler objects, for packs that declare `shadowtex0` both ways — `lib/targets.zig`
- [x] LabPBR `specular` from Cubyz's emission and reflectivity arrays — `lib/prologue.zig`
- [x] `mc_Entity` block ids from the pack's `block.properties` — `lib/blockmap.zig`, `lib/blockids.zig`
- [x] `gbuffers_water` on the translucent chunk draw, with per-attachment blending — `lib/blend.zig`
- [x] `shaders.properties` profiles, and a generated options file listing what a pack exposes
- [x] In-game pack picker — `Settings -> Shaders`, listing everything in `shaderpacks/`
- [x] In-game screen for a pack's own options — `Settings -> Shaders -> Pack options...`
- [x] Synthesised attributes declared at the pack's own width — `prologue.AttributeTypes`
- [ ] Remaining gbuffers programs (entities, particles, item drops)

`zig build test` runs **185** unit tests for this mod alongside the engine's 73; all pass. It was
202 before this tree was reconstructed from conversation transcripts — the 17 absent ones live in
source no transcript ever recorded. See `RECOVERY.md` at the repository root.

`zig build -Doptimize=ReleaseFast` produces a working `Cubyz.exe` with the module linked in.
Verified end to end against Nostalgia v5.1: **49 programs, 29 passes**, all four geometry programs
compiling against the prologue, 73/73 custom uniforms evaluating, and a run with zero `[error]`
lines and zero GL undefined-behaviour warnings.

**Three packs are present in this tree**: Nostalgia v5.1 (the fixture), Kappa v5.3 and
Complementary Unbound r5.8.1. Sildur's, photon v1.3b and Sundial Lite v1.1.0 were lost with the
old tree and need re-downloading — but everything the bridge learned from them is still recorded
below, and the code that learning produced is still here.

### Verified on hardware

Run in the client on an NVIDIA RTX 4070, in the bundled `ShaderTest` flat world:

    [info]: irisbridge: loaded Nostalgia_v5.1 (49 programs, 30 passes in the chain)

**All 30 post-chain passes compile and link against a real driver**, the chain executes every
frame, and the pack's `final` output reaches the screen — the HUD still draws correctly on top of
it, which is what confirms the hand-off is in the right place.

**The image was blown out to white when this was first written**, because Nostalgia's `deferred`
programs are physically-based and read normals and material data from `colortex1`/`colortex2`, which
nothing wrote yet. That is long fixed — the pack's own `gbuffers_terrain` runs on Cubyz geometry and
fills them. The pack now renders its sky, shadows, volumetrics, water and wind effects, and the
remaining known gaps are listed under "Still wrong".

Two driver-reported problems found and fixed this way, neither of which any amount of unit testing
would have caught:

- **`MC_*` macros were missing.** Nearly every program failed with `undefined variable
  "MC_SHADOW_QUALITY"`. OptiFine and Iris inject a standard macro set that packs use with no
  `#ifdef` guard at all. Now supplied by `pipeline.standardMacros`, following Iris's
  `StandardMacros`.
- **Render targets had no storage.** Loading happens lazily on the first rendered frame, which is
  *after* `updateViewport` has run, so `updateSize` never fired and every attachment was a texture
  name with no storage — `GL_INVALID_FRAMEBUFFER_OPERATION` on every pass. Storage is now
  allocated during load.

### The vertex-pull prologue compiles

    [info]: irisbridge: gbuffers_terrain compiled against the Cubyz vertex prologue

This was the open question for the whole approach, so it was answered before rerouting any draw
call. Nostalgia's `gbuffers_terrain` — with `mc_Entity`, `mc_midTexCoord`, `at_tangent`, its whole
`/program/gbuffer/solid.vsh` include chain and its PBR fragment stage — compiles and links against
a prologue that synthesises every one of those inputs from Cubyz's SSBO pull, on a real driver.

Two mechanics make it work, both in `lib/prologue.zig` and `glsl.zig`:

- The pack's `main` is renamed to `cubyz_packMain`, and the prologue supplies the real `main`,
  which runs the SSBO pull first and then calls it. There is no way to inject a statement into the
  top of someone else's function, and this sidesteps needing to.
- That call needs a **forward declaration**, because the pack's body is spliced in after the
  prologue and GLSL demands declaration before use. Without it the driver reports
  `undefined variable "cubyz_packMain"` — which is exactly what the first run said.

When a stage fails, the generated source is written to `irisbridge_dump/<program>.<stage>.glsl`.
That matters more than it sounds: the driver reports line numbers into source that exists nowhere
on disk, since it is assembled from pack files, the shim and the prologue.

What is *not* done: Cubyz's terrain draw call still runs Cubyz's own shader. Compiling the pack's
program proves the bridge is sound; routing geometry through it is the next step.

### Custom uniforms — what fixed the white screen

Packs declare uniforms as *expressions* evaluated every frame:

    uniform.vec2.viewSize   = vec2(viewWidth, viewHeight)
    uniform.vec2.taaOffset  = vec2((frameR2X * 2.0 - 1.0) / viewWidth, ...)
    uniform.float.frameR1   = frac(0.5 + frameCounter / 1.61803398874989484820458683436563)

Nostalgia has 73 of them. With nothing supplying them they all read zero, the pack divides by
`viewSize`, and the resulting NaN propagates through every downstream pass — a blown-out white
screen is what a NaN looks like at the end of a PBR chain.

`lib/expression.zig` implements the language; `lib/customuniforms.zig` handles declarations,
dependency ordering and upload. `CUSTOM_UNIFORM_SPEC.md` records where each rule came from.

Three parts are counterintuitive and are not mistakes:

- **The tokenizer is position-sensitive.** `gbufferModelViewInverse.0.0` is *two member accesses*,
  while `shadowModelViewInverse.2.0 * 1.0` is two accesses followed by a genuine float literal. The
  same `.digit.digit` sequence lexes differently depending on what precedes it, so a conventional
  greedy-float lexer cannot read this language at all.
- **`&&` and `||` share one precedence level**, as do all six comparisons — so `a || b && c` is
  `(a || b) && c`, not C's grouping. Iris has a checked-in fixture asserting this.
- **Matrix access yields a column.** Cubyz's `Mat4f` is row-major and uploaded with `GL_TRUE`, so a
  column is a gather across rows. Reading `rows[i]` instead would silently transpose every
  direction a pack derives from `gbufferModelViewInverse` — wrong sun and shadow directions, and no
  error anywhere. There is a test that fails if this is reversed.

Deliberate divergences from Iris, each because bug-compatibility would be a trap: `min`/`max` with
three or more arguments compute correctly (Iris ignores everything after the second); a dependency
cycle drops the cyclic group rather than disabling the whole pack; the unreachable `ivecN`/`bvecN`
family is omitted.

Verified in-game against Nostalgia: **73 declared, 73 parsed, 73 evaluable**, with exactly the two
drops the spec predicted for this host — `RW_BIOME_Dry` needs a `biome_category` input Cubyz has no
equivalent for, and `RW_BIOME_Dryness` depends on it. Both are logged once and never uploaded, so
the shader sees GL's zero rather than a wrong number.

## It renders

Nostalgia's `gbuffers_terrain` draws Cubyz's chunk geometry, its `shadow` program builds the shadow
map, and its deferred and composite chain shades the result. **Block textures, shadowed pit
interiors, atmospheric horizon** — a Minecraft shaderpack rendering a Cubyz world.

### Pass ordering: `prepare` runs *before* geometry

The last bug to fall, and the one that looked least like a bug. Iris's order is

    shadow → prepare → gbuffers → deferred → composite → final

Nostalgia's `prepare1` includes `skyboxApply.fsh`, whose `RENDERTARGETS: 0` writes the skybox into
**colortex0** — the same buffer the terrain albedo lives in. The intended sequence lays the sky down
*first* and draws terrain over it. Running `prepare` after geometry instead paints the sky straight
across the albedo, so every surface loses its texture while the scene otherwise looks plausible.

Two details make this easy to get wrong:

- The `RENDERTARGETS` directive is in an **included** file, not in `prepare1.fsh`, so it is
  invisible unless you resolve includes first.
- Because `prepare` can flip a buffer, the gbuffers stage's own read/write sides depend on it. The
  flip sequence is therefore resolved across `prepare…, gbuffers, deferred…, composite…, final`
  with a synthetic entry standing in for the terrain draw, rather than assuming geometry writes the
  unflipped side.

Fixes, in the order they were needed, each invisible to the one before it:

1. **Custom uniforms**, or every pass divides by a zero `viewSize` and NaN saturates the output.
2. **A depth attachment on the gbuffers framebuffer.** Terrain had nowhere to write depth, and
   `importWorld` was copying depth from Cubyz's framebuffer, which terrain no longer renders into.
   Every composite pass therefore read far-plane depth and concluded the whole screen was sky.
3. **A real GL projection matrix**, per the section above.
4. **`noisetex`/`normals`/`specular`**, or unassigned samplers read texture unit 0 — the buffer
   being written — as a feedback loop.
5. **Geometry writing the flip side the chain reads**, or albedo lands where nothing looks.
6. **`prepare` before geometry**, or the skybox overwrites the albedo.

A fourth fix followed, for a bug with a nastier failure mode than the others. Packs sample three
textures the game is expected to supply — `noisetex`, and the LabPBR `normals` and `specular` maps —
and none were provided. **An unassigned sampler uniform reads texture unit 0**, which during the
terrain pass is `colortex0`, the buffer that pass is writing. So `normals` was not reading black; it
was reading a feedback loop, feeding undefined values straight into the lighting maths.
`lib/packtextures.zig` now loads the pack's own noise texture (packs tune their effects to it) and
supplies neutral 1×1 LabPBR constants, which is an honest "no material data here" rather than an
invented approximation of some.

### Inspecting the G-buffer

`Settings -> Shaders -> Show G-buffer` steps through the colortex buffers live: `off` renders
normally, `colortex0`-`colortex15` blits that buffer straight to the screen and skips the composite
chain entirely. It takes effect on the next frame with no reload, because `runPostChain` reads the
setting every frame anyway.

The same thing is `shaderDebugBuffer` in the settings file — `debug_settings.zig.zon` for a debug
build, **`settings.zig.zon` for a release one**, which is what `play_windows.bat` runs. Getting that
distinction wrong means editing a file the running game never reads. The in-game control avoids the
question, and avoids a relaunch per buffer, which is what looking at six of them used to cost.

This is worth more than it looks. The composited image says almost nothing about *which* stage
produced a wrong pixel, and two rounds of reasoning from it produced plausible wrong theories. The
first look through this view answered the question immediately: `colortex0` was pure black.

That was the cause of "no blocks, just block borders". The gbuffers pass was writing to the **alt**
side of every colortex while the first composite pass read **main** — so albedo went into a buffer
nothing read, and the deferred passes reconstructed terrain silhouettes from depth alone. The flip
sequence begins *after* geometry, so the gbuffers stage must write the unflipped side; it was
picking up the default `PassBindings`, which write to alt.

Nothing errored. GL was clean throughout, every program compiled, and depth was correct — the
symptom was purely that surfaces had no colour.

### The shadow pass

> **This section describes the shadow *map*, which was correct all along. What was not is what the
> pack did with it: `shadowtex1` was never rendered into, so for most of this mod's life nothing in
> the scene was shadowed at all. See "`shadowtex1` was never rendered into" below before treating
> anything here as the whole story.**

The pack's `shadow` program runs on Cubyz's chunk geometry through the *same* vertex-pull prologue
as `gbuffers_terrain` — rendering from the light is a matter of substituting `gl_ModelViewMatrix`
and `gl_ProjectionMatrix` for the shadow camera's, not a separate code path.

`matrix.shadowModelView` builds the light basis explicitly rather than via a look-at helper, so the
degenerate case is visible in the code: with the sun directly overhead the natural up vector is
parallel to the light and the cross product collapses. The fallback picks a different axis instead
of emitting NaNs, which would blank the shadow map for a few frames around noon.

`chunk_meshing.drawChunksForShadow` deliberately is *not* `drawChunksIndirect`. That function runs
occlusion queries which write each chunk's visibility back into the chunk buffer; running them a
second time from the light's viewpoint would overwrite what the camera pass computed and cull the
next frame against the wrong viewpoint. It also reuses the camera's visible chunk list, so only
camera-visible chunks cast shadows — wrong for an occluder just outside the view, and the first
thing to revisit if shadows pop at the screen edge.

Occlusion is visibly working: trench walls shade correctly against the surrounding ground.

This work also turned up a latent GL error. Attachment loops ran over all 16 colortex slots, but
`GL_MAX_COLOR_ATTACHMENTS` is 8 on this driver, and touching an attachment past the limit is an
error rather than a no-op. The limit is now queried once and every such loop is clamped to it.

### Pack options, and why textures looked misaligned

Packs expose user-configurable options as `#define NAME value //[a b c]` in their source, with
sliders and profiles declared in `shaders.properties`. Iris parses those, shows them in a settings
screen, and injects the chosen values as defines. **That system is not implemented here**, so a
pack silently falls back to whatever its source declares.

Nostalgia declares:

    #ifndef ResolutionScale
        #define ResolutionScale 0.75
    #endif

and `solid.vsh` ends with `VertexDownscaling(gl_Position)`, which squeezes geometry into a 75%
sub-rectangle that the composite chain upscales again. The result is block textures that look
blurry and misaligned with the voxel grid — not a UV bug, a dynamic-resolution feature running with
nobody to turn it off.

The clue had already appeared and been misread: the `colortex0` debug capture showed content in a
sub-rectangle with black around it, which was written off as a blit sizing quirk.

`lib/options.zig` now handles this properly. Overrides live beside the pack:

    shaderpacks/NostalgiaZip.options.txt
    ResolutionScale = 1.0

They are applied by **rewriting the option's own declaring line**, which is what Iris does
(`OptionAnnotatedSource` is line-based for the same reason). Injecting `#define NAME value` ahead of
the source instead would collide with the pack's own definition: redefining a macro with a different
value is not portable, and on drivers that allow it the pack's line wins anyway. Booleans are
toggled by commenting or uncommenting their `#define`, exactly as a settings screen would.

Only names that are explicitly overridden get touched. Rewriting everything that merely *looks*
like an option would risk mangling ordinary internal constants, so discovery is used for reporting
and nothing else.

**Profiles.** `profile.Low`/`Medium`/`High`/`Ultra` are the presets a pack tunes as its *intended*
configurations; the raw `#define`s in the source are whatever the author last left there, which is
frequently not one of them. Select one with a `profile` line in the options file:

    shaderpacks/Nostalgia_v5.1.options.txt
    profile = High

Order is significant twice over, in opposite directions. *Within* a profile the last entry wins,
which is what lets `Medium` inherit `Low` and then raise `shadowMapResolution` from 1024 to 2048.
*Against* the user's own overrides the profile loses, because a value someone typed is a decision
and a profile is only a default. `!program.x` entries disable programs, on the same names
`shaders.properties` uses for `program.x.enabled`. A recursive profile drops the repeat rather than
hanging.

**The options file writes itself.** On first load of a pack, if no options file exists, one is
generated listing every option the pack puts in its own settings screens, with its current value and
the values it accepts, plus the profiles it ships. Every line is commented out, so a fresh file
changes nothing until it is edited.

The option list comes from the pack's `screen`/`screen.*`/`sliders` keys rather than from scanning
for `#define`. That is the author's own curation: Nostalgia declares several hundred defines, of
which a few dozen are options and the rest are internal constants. A pack that declares no screens
falls back to options that carry a `//[a b c]` list, since without one an option is indistinguishable
from a constant.

**Picking a pack in game.** `Settings -> Shaders` lists every pack in `shaderpacks/` plus a "None"
entry for Cubyz's own rendering, and is reachable from the title screen and from the pause menu.

The window sets `settings.shaderPack` and nothing else. That is deliberate: the render hook already
polls that setting once a frame and rebuilds the pipeline when it changes, on the render thread,
where a GL context exists. Loading from the GUI callback instead would be doing it on the wrong
thread at the wrong point in the frame.

Listing the packs is the one hook that reports *into* the engine, and it fills a caller-owned list
rather than returning a slice — the generated no-mod stub has to synthesise a return value, and
there is no valid zero for a non-optional slice. A `void` hook that appends nothing degrades to "no
packs offered", which is exactly right when the mod is absent.

**The pack's own options in game.** `Settings -> Shaders -> Pack options...` lists what the pack puts
in its own settings screens — its profile presets first, then each option — and clicking one steps to
the next value it accepts. `<` steps back, which matters because a pack's sliders declare long lists
(Sildur's `shadowDistance` offers 35 values) and a forward-only control makes overshooting cost a
full lap. `x` appears on rows the user has set and drops the override.

Three decisions worth stating, because each had a wrong-looking easy alternative:

- **The screen edits `<pack>.options.txt` rather than keeping its own state.** One place a choice
  lives, whether it was clicked or typed, so the two cannot disagree. `options.updateFile` rewrites
  the option's line in place, keeping the `# one of: …` hint and any notes around it — regenerating
  the file from the option list would discard both.
- **Clearing comments the line out instead of deleting it**, so the option and its legal values stay
  visible in the file. Without a way back, a screen that can set a value but never unset one pins
  every option to whatever it was last clicked to.
- **It reloads by setting a flag, not by loading.** The pack name has not changed, so `ensureLoaded`'s
  name comparison would skip the reload; `reloadRequested` forces it. The reload itself happens on
  the render thread on the next frame, where a GL context exists — and `loadedFor` is freed only
  there, so the GUI thread never hands the render thread a dangling pointer to compare against.

`ShaderPackOption` lives in `src/renderer.zig` rather than in the mod, because it is the *interface*
between them: the generated no-mod hook has to name the type in its signature whether or not the mod
is installed. Like `listShaderPacks`, `listPackOptions` fills a caller-owned list rather than
returning a slice, so the absent-mod stub degrades to "no options offered".

An option with nothing to choose between is skipped rather than shown as a dead row — a screen that
cycles values cannot operate one that has no values to cycle.

### Block identity: what makes foliage wave and water read as water

A pack decides what waves, what glows and what is water by comparing `mc_Entity.x` against numbers
it declared itself in `block.properties`. With that pinned at 0, every one of those tests failed.

`lib/blockmap.zig` reads the file and matches Cubyz's blocks into it. There is no authoritative
mapping and there cannot be one — Cubyz is a different game — but its naming overlaps Minecraft's
heavily: `water`, `lava`, `ice`, `glass`, `torch`, `lantern`, `leaves`, `oak_log`, `sand`, `gravel`
and around forty more are spelled identically. So the **namespace is ignored and the path is
matched**: `cubyz:water` matches the pack's `minecraft:water`, because comparing namespaces would
match nothing at all and the feature would be dead on arrival.

Names that mean different blocks in the two games are rewritten first, by
`blockmap.minecraftEquivalent` — `cubyz:grass` is a solid ground cube while Minecraft's `grass` is a
plant. See "`cubyz:grass` is a ground block" below for why that one mattered enough to need its own
rule.

One generalisation on top, and it earns its place: a pack entry also matches when it ends with `_`
followed by the Cubyz path. Minecraft splits by wood type where Cubyz does not, so packs list
`oak_leaves birch_leaves spruce_leaves …` and never a bare `leaves`, while Cubyz has exactly one
`cubyz:leaves`. Without it the most visible foliage in the game would match nothing. The underscore
is required, so `seagrass` does not match `grass` — different plants, different waving behaviour.

Three things about the delivery mechanism are worth writing down:

- **The table is keyed by texture index, not by block.** Despite the field being called
  `blockAndQuad`, a chunk face carries only a `texture: u16` — the block type is not recoverable in
  the shader, and putting it there means widening the hottest buffer in the renderer. So the mapping
  is inverted on the CPU: every one of a block's sixteen orientation textures is stamped with that
  block's pack id. The cost is that two blocks sharing one texture must share one id, which is
  counted and reported rather than resolved silently. The blocks packs care about all have textures
  of their own.
- **`block.properties` needs a preprocessor.** Nostalgia gates its modern names on
  `#if MC_VERSION >= 11300`, and the `#else` branch *redeclares the same keys*. Reading the file
  without evaluating conditionals does not merely miss the modern names, it replaces them with
  Minecraft 1.12 ones. `lib/preprocess.zig` is a small C-style `#if` evaluator, because that is what
  Iris uses (`org.anarres.cpp`) — and specifically **not** `expression.zig`, whose deliberately
  shared `&&`/`||` precedence matches a custom-uniform quirk that would be wrong here.
- **The SSBO must always exist.** The prologue calls `cubyzBlockIds.length()` unconditionally, and
  `.length()` against an unbound binding point is undefined rather than zero. "Nothing to map" is
  therefore a real one-element buffer of zeroes, not an absent one — which matters because the pack
  loads on the first rendered frame, often before a world has registered any blocks at all.

State predicates (`tall_grass:half=upper`) are dropped and counted: Cubyz's block `data` is a
rotation code with no named states, so there is nothing to compare against. Tag entries (`%logs`)
are matched against Cubyz's own tags, and lose to a block named outright.

### Water and per-attachment blending

Translucent chunk meshes are the same SSBO geometry as the opaque ones — the mesher sorts them into
a second list — so `gbuffers_water` needs no new geometry path, only the pack's own program over the
same prologue. `chunk_meshing.transparentOverride` does that.

It must also **enable depth writes**, which Cubyz's transparent pipeline disables. Packs measure
water thickness from the difference between `depthtex0` and `depthtex1`, so translucents that write
no depth are measured as infinitely thin. See "Water was transparent because translucents wrote no
depth" below.

Unlike the opaque override, this one **must** replace the blend state as well as the program.
Cubyz's transparent pipeline uses *dual-source* blending: its shader emits a per-channel blend
factor as colour index 1, which `dstColorBlendFactor = src1Color` reads. A shaderpack program has no
such output, so leaving that state in place blends against an undefined source.

The replacement comes from the pack's own `blend.*` declarations, and the per-buffer form is the
part that matters. Nostalgia writes:

    blend.gbuffers_water.colortex1=off
    blend.gbuffers_water.colortex2=off
    blend.gbuffers_water.colortex3=off

`colortex0` keeps alpha blending, because that is how water tints the scene behind it.
`colortex1`-`3` hold normals and material data, and those must be **written, not blended** — a
half-transparent surface whose normal is 40% mixed with the normal of whatever is behind it is not a
normal, and every deferred pass downstream reads it as though it were. Applying one blend mode
across all attachments corrupts the G-buffer in a way that looks like a lighting bug.

Two details that are easy to get wrong, and are tested:

- The key names a **colortex**; `glBlendFunci` indexes a **draw buffer slot**. Those coincide only
  when `DRAWBUFFERS` happens to be in order, so the program's own draw buffer list is what maps
  between them.
- `glEnable(GL_BLEND)` does not undo `glDisablei`. The indexed enables are separate state, so a
  `blend.gbuffers_water.colortex1=off` left behind would switch off blending on attachment 1 for
  everything Cubyz draws afterwards. `endTranslucent` clears them.

The terrain pass deliberately does *not* get this treatment: it keeps Cubyz's raster state, as
described above, and that path is already verified working.

### The gbuffers stage is not part of the flip sequence

The observation that cracked this was "the sun blob glows over blocks, even in caves". A sun visible
through solid rock is not a temporal artifact or a bad uniform — it means the sky and the terrain are
in **different textures**, and something downstream is reading the sky one.

Nostalgia's `prepare1` writes the sky *and the sun disc* into colortex0 before geometry, expecting
terrain to paint over it. Under the composite ping-pong convention — read one side, write the other —
the geometry pass wrote the opposite texture from the one `prepare1` had just filled. Two images,
neither complete: one all sky, one all terrain.

Iris says so explicitly, in `RenderTargets.createGbufferFramebuffer`:

    ImmutableSet<Integer> stageWritesToMain = invert(stageWritesToAlt, drawBuffers);

The geometry framebuffer **inverts** the flip set, and the `BufferFlipper` is not advanced across the
stage at all — `flippedAfterPrepare` is handed straight to the deferred renderer. Geometry draws
*over* what prepare left; it is a continuation of the same image, not another ping-pong step.

So the synthetic pass that used to stand in for the terrain draw is gone. Geometry now writes the
side the first post-geometry pass reads, which is by construction the side the last `prepare` wrote:

    gbuffersBindings = allBindings[prepareCount];
    gbuffersBindings.write = gbuffersBindings.read;

This also retires the note in an earlier section claiming the gbuffers stage "must write the
unflipped side" — that was the right observation about a symptom and the wrong rule. The rule is
that it writes whichever side prepare last wrote, which is only the unflipped side when no prepare
pass touched that buffer.

### The flicker is TAA, and every CPU input to it is provably correct

Confirmed by bisect: setting `taaEnabled = false` stops it. So the trigger is temporal
anti-aliasing, which is also the only effect whose output depends on camera *motion* — matching the
measurement that the image is perfectly stable while the camera is still (centre pixel over 24
consecutive frames converges smoothly and never oscillates).

Every input `ReprojectView` consumes has since been measured rather than assumed:

| input | measured |
|---|---|
| `gbufferPreviousModelView` | **exactly** the previous frame's `gbufferModelView`, drift `0.00000000`, while the camera rotates 0.014-0.195 rad/frame |
| `previousCameraPosition` | carried from the prior frame's snapshot |
| `depthtex1`/`depthtex2` | filled at the pre-translucent split, so the `hand` test resolves |
| `taaOffset` | uploaded before the draw that reads it |
| `colortex6`/`colortex9` history | `Clear = false`, written twice per frame so they end unflipped, latest content in `main` where the next frame reads |

So the reprojection maths is being fed correct values, which rules out the whole class of bug that
produced the earlier ordering and `playerPos` fixes.

**The leading remaining hypothesis is Cubyz's occlusion culling**, and it is worth writing down
because it is structural rather than a mistake. `drawChunksOfLod` draws in two batches with a GPU
occlusion query between them, and the second batch is gated on `onlyDrawPreviouslyInvisible` — that
is, on the *previous frame's* visibility. Under rotation, chunks entering the view are drawn a frame
late. Geometry that appears a frame late is precisely what a temporal filter cannot reconcile: the
history has no sample for it, so it flickers until it stabilises. Minecraft has no equivalent scheme,
so no pack is written to tolerate it.

That would also explain why the flicker resisted every uniform-level fix: nothing about the values
is wrong, the *geometry* is arriving on a different schedule than the pack assumes.

### The flickering sun, and one hypothesis killed by measurement

Nostalgia derives the world-space sun itself, in `shaders.properties`:

    sunDirX = gbufferModelViewInverse.0.0*sunPosition.x + .1.0*sunPosition.y + .2.0*sunPosition.z

That is `inverse(view) x viewSpaceSun`, and it must come out **constant while only the camera turns**.
If `sunPosition` and `gbufferModelViewInverse` disagreed even slightly, the derived sun would wobble
with view angle and move around inside the sky capture — which is precisely what "the sun flickers in
and out as I look around" describes. It was a good hypothesis and it was wrong:

    yaw=-1.617 pitch=-0.843  sunView=(-22.26,-22.78,-94.79)  sunWorld=(-78.98,55.59,25.92)
    yaw=-1.599 pitch=-0.786  sunView=(-23.68,-17.11,-95.64)  sunWorld=(-78.98,55.59,25.92)
    yaw=-1.587 pitch=-0.706  sunView=(-24.62,-9.22,-96.48)   sunWorld=(-78.98,55.59,25.92)

The view-space sun moves as it should and the world-space sun is bit-for-bit constant. Normalised it
is `(-0.79, 0.56, 0.26)` — above the horizon, correct for daytime. The matrix column convention, the
celestial construction and the inverse are all consistent.

Which leaves the sky capture's size, fixed in the same round. The sun is *baked into* that capture by
`skyboxPrep` and read back by direction; with the buffer allocated at screen size instead of the
declared 256x256, the sun's texels landed at a UV unrelated to where the sampling looked for them —
present in some view directions, absent in others.

Worth keeping as a method note: three sun hypotheses were proposed across this work and two were
killed in minutes by measuring an invariant rather than by staring at frames. The invariant here —
"this quantity must not change when only the camera rotates" — is the kind of property worth reaching
for, because it needs no reference image to check against.

### Fixed-size buffers, and why `gbuffers_skybasic` was the wrong thing to build

Reading the missing-program list suggested implementing `gbuffers_skybasic` to get the pack's sky.
Opening it first showed why that would have rendered nothing at all:

    #if MODE == 0
        void main() {gl_Position = vec4(-1.0);}   // vertex: collapse it
    #else
        void main() {discard;}                    // fragment: throw it away
    #endif

Nostalgia *deliberately discards* the vanilla sky geometry. It draws its sky entirely in the
prepare/composite chain, which already runs here in full. So the missing sky was never a missing
program.

`prepare` renders a **sky capture** into `colortex4` through a directional projection, and `prepare1`
samples it with `projectSky(direction)` to reconstruct the sky per pixel. The pack declares:

    size.buffer.colortex4=256 256
    size.buffer.colortex10=1024 512
    size.buffer.colortex11=1024 512

`size.buffer.<name>` was not implemented — every colortex was allocated at screen resolution. So the
sky capture was written into a 1280x720 buffer through maths expecting a 256x256 square, and sampled
back through the same mismatch. The result is a sky reconstructed from the wrong part of the wrong
texture, which is the flat wash that survived every earlier fix.

Buffers now carry their declared size, and — the part that is easy to miss — **the viewport follows
the buffer a pass draws into**. A pass writing a 256x256 capture with a full-screen viewport would
render it into one corner of its own texture and leave the rest untouched. `viewportFor` takes the
size from the pass's first draw buffer, and `swapFlippedBuffers` copies the target's own extent
rather than the screen's.

The lesson is the same one this file keeps recording: the fix was found by reading the pack's
declarations, not by looking at the image, and the plausible-sounding job would have been wasted
work. Checking `gbuffers_skybasic.fsh` cost a minute.

### The noise texture was guessed at rather than read

`texture.noise` in `shaders.properties` states outright where a pack keeps its noise texture, and the
loader ignored it in favour of trying three conventional filenames. That worked for Nostalgia by
coincidence — it does keep its noise at `image/noise2D.png` — and failed for Complementary, which
declares `lib/textures/noise.png`.

The failure was silent by construction: a pack shipping no noise at all is legitimate, so the
fallback generated hash noise and logged that it had. Every noise-driven effect Complementary has —
clouds, water, dithering — was running against a texture it never received. Now:

    NostalgiaZip     loaded noise texture image/noise2D.png (256x256)
    Complementary    loaded noise texture lib/textures/noise.png (128x128)
    Sildur's         pack ships no noise texture, generated one at 128x128

Sildur's genuinely ships none, and now gets the generated fallback at the size *it* declared rather
than a hardcoded 256.

The remaining `shaders.properties` keys were checked against the fixtures rather than implemented
speculatively: `scale.` is used by none of the three, `alphaTest.` only by Complementary and only for
programs this pipeline does not run — except `gbuffers_water` — and `texture.<stage>.<sampler>` mostly
points at Minecraft assets Cubyz does not have. Those are recorded here rather than built.

### Parsed but never used

Three bugs in a row shared a shape — a value the loader read correctly and then nobody consumed —
so the whole of `pack.Settings` got walked field by field, checking each is actually reached by
something outside `pack.zig`. Four of the ten were not:

| directive | state |
|---|---|
| `shadowMapResolution` | parsed, texture hardcoded to 1024 — **fixed** |
| `shadowcolorFormat` | parsed, textures hardcoded to RGBA8 — **fixed** |
| `noiseTextureResolution` | parsed, generated noise hardcoded to 256 — **fixed** |
| `shadowMapFov`, `shadowHardwareFiltering`, `ambientOcclusionLevel` | cannot be honoured — now listed in `unsupportedDirectives` |

`shadowcolorFormat` matters for the same reason the colortex formats do: a pack storing world-space
positions or normals in its shadow colour buffer asked for a float format and was getting eight bits
per channel. `noiseTextureResolution` matters because the pack divides by that constant to derive
its sampling coordinates, so a different size puts every noise lookup at the wrong scale.

This class is worth naming because it is invisible to every other check here. The uniform coverage
report cannot see it — the uniform *is* supplied, just wrongly. Nothing errors, nothing is missing,
and the parsing code looks finished. The only thing that finds it is asking, of each value the
loader extracts, *who reads this?*

`unsupportedDirectives` exists so the remaining three cannot quietly rejoin that category. It mirrors
`uniforms.unsupported`, and carries the reason rather than just the name — `ambientOcclusionLevel`
is not unimplemented laziness, it is that Iris scales Minecraft's baked per-vertex AO and Cubyz's
per-vertex light has no separable occlusion term to scale.

### The shadow map ignored the size the pack asked for

`const int shadowMapResolution` was parsed into `pack.Settings` and then never used — the texture
was allocated at a hardcoded 1024 whatever the pack declared.

That is not a quality setting the host gets to pick. The pack compiles the same constant into its
own shaders and divides by it to get a texel size, so allocating a different size makes every filter
radius and depth bias wrong at once: shadow acne on surfaces near the light, over-blurring
elsewhere, and a penumbra that does not match the geometry. Nostalgia's profiles ask for 1024, 2048
or 4096 depending on preset, so anyone selecting anything but Low got a mismatch.

The texture now follows the pack, clamped to `GL_MAX_TEXTURE_SIZE` so a request the hardware cannot
meet degrades instead of silently failing to allocate.

This is the same class as the fog units and the LabPBR mapping: a value that *was* being read but
then not honoured, which is harder to spot than one that is missing outright, because the parsing
code looks complete.

### Fog distances were altitudes

`fogStart` and `fogEnd` are **distances from the camera**. Cubyz's `fogLower`/`fogHigher` are
**altitudes** — its fog is a height band, not a ramp along the view ray. They were handed straight
across, so packs were told fog begins 100 blocks away and is total by 1000.

That is a unit error rather than an approximation, and Sildur's shows why it matters: twenty-four of
its files compute

    mix(albedo, fogColor, (dist - fogStart)/(fogEnd - fogStart))

so everything past a hundred blocks dissolved toward fog colour and the sky, being furthest of all,
went to solid fog. The same flat wash the missing skybox produced, reached by a different route —
which is worth noting, because fixing one of the two would have looked like fixing neither.

`fogDistances()` now derives both from the render distance, which is what the value means: fog
exists to hide the edge of the loaded world, so it has to end where the world does. One definition
feeds both the `fogStart`/`fogEnd` uniforms and the `gl_Fog` struct, so the two cannot drift apart
and describe different fog to the same shader. `fogMode` is now `GL_LINEAR` rather than 0, which is
not a GL fog mode at all.

Complementary declares none of these, which is why it was unaffected — and a reminder that "looks
broken" has a different cause per pack even when the symptom matches.

### The sky was never in the G-buffer

The sky came out a flat teal-grey with no gradient and no sun, and reasoning from the composited
image produced several confident wrong answers. One look at `colortex0` through
`shaderDebugBuffer = 0` settled it in seconds: terrain albedo correct, **sky region pure black**.

Minecraft draws its sky *as geometry*, during the gbuffers stage, so by the time a pack's deferred
passes run `colortex0` already holds sky wherever terrain does not cover it. Cubyz draws a skybox
too — but into its own framebuffer, which the pack never sees once `gbuffers_terrain` takes over the
terrain draw. So the composite chain was applying atmospheric scattering to black, and flat fog
colour is what that produces.

`targets.importSky` blits Cubyz's rendered sky into the albedo target immediately before the terrain
draw, restoring the invariant packs are written against. Only the first draw buffer is touched; the
rest carry material data a sky colour would corrupt.

Worth recording as method rather than as a fact: five candidates were ruled out before this — the
flip state across frames, `flip.<program>.<buffer>` directives, the fog uniforms, `upPosition` and
the celestial construction, and a `skyCaptureResolution` the coverage report flagged. Each was
dismissed in minutes by reading the Iris source or grepping the pack, and each would have cost hours
to implement. The one measurement that actually located the bug was cheaper than any of them.

### Nothing accumulated across frames

The ping-pong resolution was right *within* a frame and wrong *between* them, and the difference is
one copy at the end of the frame.

A buffer written once per frame reads `main` and writes `alt`. The flip sequence is resolved once at
load, so the next frame does the same thing: reads `main`, writes `alt`. Its newest contents are
always in `alt` and it always reads `main` — **a texture nothing ever writes**. Every value a pack
carries between frames was therefore reading a cleared buffer: TAA history, auto-exposure, every
smoothed quantity.

Auto-exposure is the one that shows. It cannot settle if it recomputes from nothing each frame, so
it swings with whatever is on screen — the sun appearing to blink in and out as the exposure lurches,
and a scene that is washed out from one angle and dark from another.

Iris solves this with **swap passes** in `FinalPassRenderer`, and its own comment is the clearest
statement of the fix: *"we merely copy it from alt to main"*. At the end of the frame, every buffer
that ends flipped gets its `alt` copied into `main`, so the next frame's read finds it. Buffers the
pack asked to have cleared are skipped, since their contents are discarded anyway.
`flip.finalState` computes which buffers qualify and `targets.swapFlippedBuffers` does the copy.

Two dead ends came first, and both were cheap to rule out by reading the Iris source rather than
guessing: the flip state does **not** advance across frames in Iris either (`BufferFlipper` is
constructed once, in `CompositeRenderer`), and none of the three fixture packs use the
`flip.<program>.<buffer>` directives that would suppress a flip. Checking those took minutes;
implementing either would have taken hours and fixed nothing.

## Finding gaps instead of chasing symptoms

The worst failure mode in this port is not a crash or a compile error — it is an **unsupplied
uniform**. A pack declares `uniform float centerDepthSmooth;`, nothing binds it, the program links
cleanly, and GL hands the shader a zero. There is no error at any level, so the pack renders
confidently wrong and the only symptom is "it looks broken", which is unactionable.

Debugging that per pack does not scale: each one is a different wrong image with the same cause.
`lib/coverage.zig` inverts it. On every load it enumerates the uniforms each program *declares*,
subtracts everything the bridge supplies — the built-in set, the pack's own custom uniforms, and
every sampler bound by texture unit — and logs what is left:

    irisbridge: Sildur's ... reads 12 uniform(s) nothing supplies, so they are zero: atlasSize,
    centerDepthSmooth, darknessLightFactor, dhRenderDistance, entityColor, ...

That turned an unbounded debugging problem into a work list. Diffing it against Iris's own uniform
providers (`common/src/main/java/net/irisshaders/iris/uniforms/`) separates real gaps from names the
pack invents for itself, and running it over all three fixtures at once shows which gaps are shared:

| pack | before | after |
|---|---|---|
| Nostalgia | 5 | 2 |
| Complementary | 46 | 30 |
| Sildur's | 12 | 7 |

`centerDepthSmooth` and `entityColor` were missing in **all three**, and `atlasSize` in two — none of
which any amount of staring at a screenshot would have named.

Two caveats on reading the report. It lists *declared* uniforms, and a declaration inside an
`#ifdef` the driver never compiles still counts, so the number overstates the gap. And most of what
remains is genuinely pack-private rather than missing: Complementary's `vx*`, `voxel_*`, `wsr_*` and
`floodfill_*` are its voxel-GI machinery, `dh*` belongs to Distant Horizons, and Iris does not supply
those either.

### What testing three packs on hardware found

Running Complementary and Sildur's rather than only Nostalgia turned up five bugs in one sitting,
none of which the Nostalgia fixture could have shown. This is the conformance harness's whole
argument, restated: a single-pack test structurally cannot see the next pack's conventions.

- **`texture(s, coord, bias)` in a vertex shader is illegal**, not merely useless — the bias is
  relative to an implicitly computed LOD and only fragment shaders have the derivatives for one.
  NVIDIA says `error C5248: Use of 'bias' argument in 'texture' is not valid for this profile`.
  Complementary's composite *vertex* stages call `texture2D` with a bias, and the shim emitted the
  same body for every stage. Outside a fragment shader the overload now uses `textureLod`, which is
  the only available reading and is what GLSL 120 required in a vertex shader anyway.
- **`ftransform()` was emitted in fragment shaders.** It transforms the incoming vertex, so it is
  meaningless there — but packs put it in headers *both* stages include, so `analyse` sees it, and
  the generated helper then referenced a `cubyz_Vertex` only the vertex stage declares.
- **A file can carry several `DRAWBUFFERS` directives behind `#if`s, and the *last* one wins.**
  Complementary's `gbuffers_terrain` declares `/* DRAWBUFFERS:06 */` and then, inside a conditional,
  `/* DRAWBUFFERS:064 */` with a write to `gl_FragData[2]`. The output array is sized by the highest
  index the source actually writes, and the directive taken is the last in the file — which is what
  Iris does, stated outright in `CommentDirectiveParser.findDirective`: `lastIndexOf(prefix)`,
  commented *"since those take precedence"*.

  **An earlier version of this paragraph said the opposite** — that slots `glDrawBuffers` never maps
  simply discard their writes, "which is what happens on Iris too" — and the loader took the *first*
  directive to match. It is worth spelling out what that cost, because the claim reads as settled and
  was checked against nothing. Complementary's third output is its **normals**. Mapping two slots
  meant the shader computed them and the driver threw them away, so its deferred pass lit every
  surface with no normal and returned black. Most of the screen rendered as flat untextured sky. The
  pack looked comprehensively broken for one wrong sentence about another program's behaviour, and
  the fix was to read fifteen lines of `Iris/` — the source this file already names as the authority
  for exactly this kind of question.
- **`gl_Fog` was unhandled.** Core removed the fog-parameter struct at 140. It is now declared as
  `cubyz_Fog` and fed from Cubyz's fog — colour and density pass through, and the linear
  `start`/`end` range comes from the render distance, since Cubyz models fog as a density and a
  height band rather than a linear ramp.
- **The generated noise texture crashed.** Sildur's is the only fixture pack that ships no
  `noise2D.png`, so it was the only one to reach the fallback — where `x*374761393` was computed in
  `usize` and then `@intCast` to `u32`, which panics on the first pixel. A hash is meant to wrap;
  the width just has to be stated up front.

- **A custom uniform's declared type is a contract, not a hint.** Sildur's writes
  `uniform.int.framemod8=fmod(frameCounter, 8)`, and `fmod` returns a float. Uploading dispatched on
  the *evaluated* type, so `glUniform1f` went to the shader's `uniform int framemod8` — rejected with
  `GL_INVALID_OPERATION: Wrong component type or count`, 20,176 times in 45 seconds, leaving the
  value pinned at 0 for every program that reads it. For a pack using it to rotate temporal sample
  patterns that is most of them, which is why the image was wrong in a way that resisted
  description. `expression.coerceTo` now converts to the declared type in both directions.

  The previous version converted int to float but not the reverse, reasoning that "nothing in the
  language returns int from a float, so a float in an `int` slot is a pack error". The premise is
  correct and the conclusion does not follow: packs write this, Iris accepts it, and refusing the
  conversion breaks the pack rather than the declaration.

Two of these are worth noting as a pattern: both the bias overload and `ftransform` were *stage*
mistakes. The shim is generated per stage and it is easy to write a rule that is right for fragment
shaders and silently illegal for vertex ones.

### The missing HUD

With a pack loaded there was no hotbar, no health bar and no pause menu. The GUI was not broken in
any way it could report: `hideGui` was false, all seven HUD windows were open and correctly
positioned, the viewport was the full window, no scissor, colour mask open, and GL raised no errors.
It was drawing perfectly — into framebuffer object 1.

`renderWorld`'s terrain-override cleanup was

    defer if (shaderpackTerrain) {
        renderhook.endTerrain();
        worldFrameBuffer.bind();     // <- wrong buffer, wrong time
        c.glViewport(0, 0, lastWidth, lastHeight);
    };

A `defer` runs at *function exit*, which here is after the composite chain **and** after
`renderHud` — and `gui.updateAndRenderGui()` runs later still, inheriting whatever is bound. So the
last thing the frame did was point the GPU at the world framebuffer, and the entire interface went
into a buffer nothing presents. It now restores the default framebuffer, which is what the
no-shaderpack path leaves and why this only ever happened with a pack loaded.

Worth noting how it hid: rendering into a complete framebuffer that nobody reads is entirely legal,
so there was nothing to warn about. The give-away was one line of a temporary diagnostic —
`glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING)` at the moment the GUI drew — after reasoning from the
symptom had produced several plausible and wrong theories about blend state.

### Ghosting and jitter: three ways to desynchronise a temporal effect

Found on hardware, and worth writing down because all four produce the *same* two symptoms —
smearing when the camera moves, and a fine shimmer that never settles — while having nothing to do
with each other. A pack's TAA jitters the projection by a sub-pixel offset each frame and relies on
temporal accumulation to average it out. Anything that stops the history lining up leaves the jitter
visible *and* smears the history, so both symptoms appear together and neither points at a cause.

1. **The uniform snapshot was taken before the camera updated.** `renderhook.beginFrame` was the
   first line of `renderWorld`, several lines ahead of `game.camera.updateViewMatrix()`. So
   `gbufferModelView` described the *previous* frame's camera while the geometry was drawn with the
   current one. Reprojection was then wrong by exactly one frame of rotation — ghosting proportional
   to how fast you turn.
2. **The player position was sampled twice.** `capture` called `game.Player.getEyePosBlocking()`
   itself, while the geometry is positioned against the `playerPos` that `main.zig` sampled and
   passed down. Two mutex-guarded reads of a value the physics thread writes land in different
   places, so `cameraPosition` sat a fraction of a block from where the chunks actually were, by a
   different amount every frame. `capture` now takes `playerPos` as an argument; it is not a value
   this code may re-derive, because it *defines* the origin of the world space the pack sees.
3. **Custom uniforms were uploaded after the draw.** `runPostChain` and `runPreparePasses` called
   `custom.upload` *after* `runPass` had already drawn, so every composite pass ran on the previous
   frame's values. Uniforms persist in the program object, so nothing read as uninitialised and no
   error was raised. It matters because the set includes `taaOffset`: the pack jitters its geometry
   by that offset and its TAA resolve subtracts the same offset back out, so a one-frame lag on one
   side leaves a sub-pixel error that never cancels. The gbuffers paths always had this right; only
   the composite loops were wrong.
4. **`depthtex1` and `depthtex2` were never written.** `importWorld` fills them only when it is also
   copying colour, which it stops doing as soon as a `gbuffers_terrain` program exists — and
   `clear()` only ever cleared `depthtex0`. So they held undefined GPU memory. Nostalgia's
   `ReprojectView` adds the camera-translation term only where `depthtex2` matches the scene depth,
   which is how it tells world geometry from the handheld item; against garbage that test fails
   everywhere, so **camera translation was dropped from the reprojection entirely** — ghosting
   precisely when you move rather than turn. All three depth textures are now cleared, and
   `captureDepthSnapshots` fills them at the point Minecraft's own split falls: after opaque
   geometry, before translucents.

The third is the most instructive. Nothing errored, GL was clean, the depth *test* worked perfectly
because that only ever used `depthtex0`, and the symptom appeared in a post-processing pass three
stages downstream of the mistake.

### The sky import destroyed the sky it was meant to supply

`importSky` blits Cubyz's rendered sky into the albedo target just before the terrain draw, to stand
in for the vanilla sky *geometry* a pack would otherwise shade with `gbuffers_skybasic`. It was
written when the gbuffers stage still wrote the opposite side from `prepare`, so the blit landed in a
buffer nothing had filled.

Fixing the flip rule — geometry writes whichever side `prepare` last wrote — made the two collide.
Nostalgia's `prepare1` runs `skyboxApply.fsh` (`RENDERTARGETS: 0`), building its gradient and sun
disc into colortex0; `beginTerrain` then blitted Cubyz's **flat clear colour plus stars** straight
over it, every frame. The pack's own sky was computed and immediately discarded, and what the
deferred chain got instead was a flat bright colour sitting in the albedo buffer — which it then lit,
scattered and fed to the auto-exposure that reads the whole screen.

The rule now is the one the invariant actually states: at the start of the gbuffers stage colortex0
holds *the sky*, and Cubyz's is needed only when the pack did not put one there itself.

    const albedoTarget = if(pass.drawBuffers.slice().len != 0) pass.drawBuffers.slice()[0] else 0;
    if(!state.preparedTargets.contains(albedoTarget)) importSky(…);

`flip.writtenTargets` computes that set, and it deliberately is **not** `finalState`: parity is the
wrong question. A buffer written twice ends unflipped and looks untouched to `finalState`, while
still very much having been written. Of the three fixture packs only Nostalgia has `prepare`
programs at all, so the split falls exactly where it should — Nostalgia keeps its own sky,
Complementary and Sildur's still get Cubyz's as the stand-in.

Worth recording as a pattern rather than a fact: this is the second time a *correct* fix in this file
turned a neighbouring workaround into a bug. The flip change was right; what it broke was code whose
correctness silently depended on the old behaviour. A workaround that compensates for a bug
elsewhere has no way to announce itself when the bug is fixed.

### Following the options file's own advice produced a broken shader

The generated `<pack>.options.txt` ships every option commented out and says to uncomment one:

    # Clouds = 3        # one of: 0 1 2 3 4

`Overrides.parse` split on the first `=` and trimmed whitespace, so uncommenting that line set
`Clouds` to `3        # one of: 0 1 2 3 4` — and that string was then written into the pack's own
declaring line. The only overrides that ever worked were hand-typed ones without the hint, which is
exactly what the existing fixture files happen to be, so nothing had shown it.

A trailing `#` comment is now stripped from the value. No option value contains a `#`.

### Sea level: the whole world was 64 blocks underground

The symptom was a sun-shaped glow that stayed on screen **through solid rock, in a cave**, flickered
as the camera turned, and washed the image out at every quality preset.

"Through solid rock" ruled out most of the pipeline immediately — but it had ruled out the wrong
things before, so this time each candidate was killed by reading rather than by guessing. Dead in
minutes: the quality profiles (the symptom survives `Low`), `gbufferProjectionInverse` disagreeing
with the rebuilt projection (it is that matrix's exact inverse), a reversed-Z depth convention
(Cubyz uses `GL_LESS` and no `glClipControl`), and the Z-up/Y-up eye basis (`matrix.gbufferModelView`
does the correct `B·V·B⁻¹`).

The cause is in `composite1.fsh`, Nostalgia's volumetric fog:

    float altitude  = rPos.y + eyeAltitude;
    vec3 density    = fogAirDensity(rPos, altitude, !isSky);
        density.x   = mix(density.x, 250.0, (1-cave) * expf(-max0((altitude - 50.0) * 0.01)));

`max0` clamps the exponent at zero, so for **any** altitude below 50 the mix factor is exactly
`exp(0)` = 1 and air density is pinned at **250** — the pack's thick valley haze, intended for deep
ravines.

Cubyz's sea level is z = 0. Minecraft's is 64, and packs treat altitude as an absolute height in
that frame rather than deriving it from anything the host tells them. `eyeAltitude` and
`cameraPosition` were handed across raw, so a player standing on a Cubyz beach reported altitude 0 —
64 blocks underground by the pack's reckoning, and comfortably under the haze threshold. **Every
point in every Cubyz world sat at maximum fog density, permanently.**

That accounts for all of it: the blob is sun-shaped because the Mie phase function peaks toward the
light, it survives through rock because fog is integrated in front of geometry rather than behind it,
it ignores quality settings because base atmosphere is not quality-gated, and it washes out exposure
because auto-exposure meters a screen full of dense fog.

The pack states the frame it expects outright, one file over, in `skyboxPrep.fsh`:

    const float eyeAltitude = 64.0;

`matrix.positionToYUp` now adds `matrix.seaLevel` where `toYUp` only rotates. Two properties are
tested because both are easy to break: the offset applies to **positions only** — adding it to a
direction would tilt every normal and light vector — and it **cancels between any two positions**, so
reprojection and camera-relative geometry are untouched. The integer/fraction split carries the same
offset, or the pair stops summing back to `cameraPosition`.

Not Nostalgia-specific: Sildur's tests `cameraPosition.y` against absolute cloud altitudes
(`cloud_height`, `maxHeight`), so it was placing the camera permanently below its cloud deck too.

This is the third bug of the same shape in this file, after `fogStart`/`fogEnd` being altitudes and
`shadowMapResolution` being ignored: **a value that is supplied, and wrong.** None of them are
visible to the coverage report, because the uniform *is* there. The only thing that finds them is
asking what frame or unit the consumer expects, and checking the pack's own source for the answer.

### The sunlit cave: `eyeBrightness` was a clock, not a place

The symptom that outlasted six wrong theories: a sun-shaped glow inside a cave, visible through solid
rock, drifting as the camera turned, unchanged at every quality preset. What finally found it was not
another hypothesis — it was **reading `logs/latest.log`**, which had been sitting on disk the whole
time and settled four questions at once.

The instrumentation in `lib/diagnostics.zig` reported, once a second:

    terrain writes 3 buffer(s), albedo is colortex0, Cubyz sky import off (pack's own prepare sky kept)
    eyeAlt=71.7 seaLevel=64 | centerDepth raw=0.982007 dist=5.56 blocks
    sunView=(-80.20,58.38,12.61) sunWorld=(-77.25,57.55,26.84) sunAngle=0.391

Which killed, in one run, the theories that would each have cost hours: the sky import was correctly
off, the sea-level offset had reached the shader, **depth was right** (5.56 blocks facing a cave wall
— so nothing was integrating over a wrong distance), and the world-space sun held steady while the
view-space one swung, so the celestial construction was sound.

That left one input, and it was wrong at the level of meaning rather than of value.
Nostalgia's fog:

    float caveMult  = linStep(eyeBrightnessSmooth.y/240.0, 0.1, 0.9);
    ...
    vec3 skylight   = lightColor[2] * cave;
        sunlight   *= cave;
        density.x   = mix(density.x, 250.0, (1-cave) * expf(-max0((altitude - 50.0) * 0.01)));

`eyeBrightness.y` is Minecraft's **sky-light level at the player's position** — 240 under open sky,
day or night, 0 deep underground. It is a property of *where you are standing*. The bridge was
supplying `dayTime.ambientLight`, which is a property of *what time it is*: 1.0 at noon and 0.1 at
midnight, identically everywhere in the world, including at the bottom of a cave.

So underground at noon the pack was told 240 — "open sky" — and dutifully lit the cave's volumetric
fog with full sunlight and full skylight. The glow is sun-shaped because the Mie phase function peaks
toward the light, it ignores the rock because volumetrics are integrated along the view ray rather
than occluded by it, and it survives every quality preset because this is base atmosphere.

`mesh_storage.getLight` supplies the real thing. `lightingData[1]` is sun, `[0]` is block —
established from `chunk_meshing`, where `[1]` is what `propagateUniformSun` writes — each RGB over
0-31, collapsed to its strongest channel exactly as the vertex prologue does for `lmcoord`, then
scaled to Minecraft's 0-240.

Three details are deliberate:

- **The sun channel is not multiplied by the time-of-day factor.** Cubyz applies that separately when
  shading, as Minecraft does, and packs expect raw exposure — `eyeBrightness.y` is 240 outdoors at
  midnight too.
- **`eyeBrightnessSmooth` is genuinely smoothed.** It is what `caveMult` reads, so stepping it
  instantly would pop the entire fog volume the moment you crossed a cave mouth.
- **An unloaded chunk reports open sky, not darkness.** Guessing "underground" would drop a cave-fog
  wall across the world for the first frames after a load.

This also retires the fourth instance of the pattern this file keeps recording, and the nastiest one
yet. The previous three — `fogStart`/`fogEnd` as altitudes, `shadowMapResolution` ignored, altitude
in the wrong frame — were values that were *numerically* wrong. This one was numerically plausible,
correctly scaled to 0-240, and reported by the coverage report as supplied. It was simply an answer
to a different question.

The sea-level fix above is still required and the two interact: outdoors `caveMult` is 1, so
`(1-cave)` zeroes the altitude term entirely — but inside a cave that term is live, and it is the
altitude frame that decides whether the cave haze is sane or pinned at 250.

### The light shaft through solid rock

> **Partly superseded.** The camera-frustum cause below was real and its fix is kept. But the beam
> outlived it, and the remaining half was `shadowtex1` never being rendered into — so the volumetric
> march read *every* sample as lit, whatever the shadow map contained. See the section on it below.

The longest-lived bug in this port, and the one that cost the most wrong answers. Symptom, in the
words that eventually solved it: *"a giant beam of light overlaying a large area of blocks at some
place on the screen or slightly out of view"*, moving opposite to the camera and dipping into the
ground, visible inside caves and through blocks outside them.

**Cause: Cubyz's shadow map only contains chunks the camera can see.** `renderShadowMap` reuses the
`ChunkLists` that `updateAndGetRenderChunks` produced against the *camera* frustum, so any geometry
outside the view — the rock behind you, the hillside off to one side — is absent from the shadow map
entirely.

For surfaces that is the mild artifact this file already warned about: shadows pop at the screen
edge. For **volumetrics it is catastrophic.** The pack marches a ray through the air and tests each
step against the shadow map to decide whether that point is sunlit. Every point whose occluder is
missing reads as unshadowed, so full sunlight is scattered through solid rock — a beam anchored in
the world, tracking the sun as the camera turns, lying flat and pointing downward near sunset
because that is where the sun is.

Confirmed by bisect: `fogVolumeEnabled = false` removes it completely, and cave lighting becomes
sensible at the same time. That much is solid — the effect is the carrier.

**`far` was the render distance, not the far plane — a major bug found on this hunt.** Minecraft's
`far` uniform is the render distance in blocks, and that is *also* where Minecraft puts its
projection far plane, so one number answers both "how far does the world extend" and "what
normalises depth". Cubyz separates them: `zFar` is 65536, chosen against z-fighting rather than to
describe the world. The bridge handed that across, telling every pack the world was 65 km deep.

`far` now comes from `fogDistances().end`, and the projection given to packs uses the same far plane
— `depthLinear` is `(2·near)/(far+near−d·(far−near))` and only agrees with the depth actually written
when those match, so changing one alone would fix ray lengths while silently corrupting every
distance reconstructed from depth.

The effect on the image was large and is worth recording as evidence the fix is real: the frame
luminance map went from a **featureless smooth wash** to genuine terrain structure with a dark
foreground and distinct regions. **It did not remove the beam.**

**Two real culls were found, and the shadow map is now verified correct.** `fillIndirectBuffer.comp`
filters chunks *twice*, and `drawChunksForShadow` was subject to both:

1. **Occlusion.** With `onlyDrawPreviouslyInvisible = 0` the live condition is
   `chunks[chunkID].oldVisibilityState != 0` — state written by the **camera's** GPU occlusion
   queries. The shadow pass drew only what the camera could see and had not occluded.
2. **Direction.** `isVisible(i%7, playerDist)` culls each face group against the **player**. For
   `dirUp` that is `playerDist.z >= 0`, and only *positive* components are clamped, so a chunk above
   the player keeps a raw negative `playerDist.z` and loses its entire up-facing group. Standing in a
   pit or cave — 8-12 blocks below the surrounding land in every logged run — that discards every
   sun-facing occluder there is.

Both are now bypassed for the shadow pass via `ignoreVisibility` and `ignoreDirection`, set
explicitly to 0 on the camera path so a stray value cannot silently disable occlusion culling on the
hot path. GL back-face culling already discards triangles facing away from whatever viewpoint is
being rasterized, so the second test was redundant for the camera and wrong for the light.

**Why fixing either alone did nothing, which cost several rounds:** they are independent, and the
second one is chunk-count-invariant. Chunks at or below the player keep `dirUp` at *any* distance, so
the low ground around the player fills in and every chunk added by widening the radius is higher
ground whose up-facing group is dropped. Coverage climbs while nearby chunks load and then stops
dead: 228 chunks → 15.4%, 934 → 22.1%, 3231 → **22.5%**. That plateau looked like a hard limit and
was in fact a geometric constant.

**Result: coverage 22.5% → 69.4%**, against ~72% predicted independently from the pack's warp and
the logged sun elevation. And the lookup itself was then measured directly — reproducing the pack's
transform, warp and `z *= 0.2` on the CPU for the crosshair point, which must find *itself* as its
own occluder: `delta = -0.00002`. **The shadow subsystem is correct end to end and is no longer a
suspect.**

The beam nonetheless survives, so the fault is in the scattering maths downstream of the shadow test
— specifically what the march multiplies the shadow term by: `lightColor` (a `flat out mat4x3`
computed in the pack's own `composite1` vertex stage from its atmosphere model, *not* a uniform the
bridge supplies) and `lightFlip`. That last one is worth checking first: it is
`clamp(1.0 - lf1, 0, 1)` over `sunY = sunDirY * sunDirNorm`, and it exists to fade sunlight out near
the horizon — which is exactly where every logged run has been sitting, at `sunAngle ≈ 0.50`.

**Candidates tried and eliminated, all now measured rather than argued:**

- **The shadow map only contained camera-visible chunks.** `renderShadowMap` reused the `ChunkLists`
  built against the camera frustum, so geometry outside the view was absent and every point behind
  it read as unshadowed. `collectShadowChunks` now enumerates every loaded chunk within the pack's
  `shadowDistance` instead. **This is a genuine fix and is kept** — it also cures shadows popping in
  at the screen edge — but it did *not* remove the beam.
- **The shadow sampler wrapping outside the shadow volume.** It already clamps to edge, as Iris does.

- **The shadow depth range.** Cubyz leaves `glDepthRange(0.001, 1)` set; the pack's shadow maths
  assumes `[0, 1]`, and against Nostalgia's `z *= 0.2` compression that is worth about a block of
  bias. **Fixed and kept** — it is wrong on its own terms — but not the cause.
- **The shadow map being empty or malformed.** Measured directly with `readShadowMap`: 460 chunks
  drawn, 17-23% of the map holding geometry in a clean warped disc, depths at 0.47-0.48 — exactly
  the `[0.4, 0.6]` band the pack's compression predicts. **The shadow map is correct.** Three of the
  fixes above were aimed at a subsystem this then proved healthy.

What is measured and no longer in question: the march samples through the same `shadowModelView` and
`shadowProjection` the working surface path uses; `gl_ProjectionMatrix` during the shadow render is
that same `shadowProjection`; and **nothing in any frame exceeds 1.0**, so this was never an exposure
or clipping problem.

What is unexplained is why the march reads *lit* where the surface path reads *shadowed*.

**The next step, and the one link never directly measured:** instrument the volumetric march itself —
compute the shadow coordinate it produces for a known point and compare it against what the shadow
pass stored at that coordinate. Every failed attempt so far assumed that correspondence and attacked
one end or the other of it. The option stays off meanwhile, with the reasoning recorded in
`<pack>.options.txt`.

### How this was actually found, and how much it cost

Worth writing down as method, because the search was far more expensive than the fix and the reason
is instructive.

Six hypotheses were proposed and shipped before the cause was located, none of which touched the
symptom: the sky import overwriting the pack's own sky, the sea-level altitude frame, `caveMult`
reading a day/night clock instead of a position, a scaling error in that same fix, and two more
killed by reading. Two were genuine bugs worth keeping. **None were this one.**

What broke the loop was instrumentation, not insight:

- **`logs/latest.log` had been on disk the whole time.** It answered in one read what several rounds
  of reasoning had not: no GL errors, all 73 custom uniforms evaluating, the pipeline healthy. The
  bug was a value, not a state.
- **A per-pass pixel trace** at the crosshair localised the jump to a single pass — `composite3`,
  0.0002 to 0.3757 — rather than "somewhere in the composite chain".
- **A 40x20 luminance map of the frame, logged as text**, showed the thing no single-pixel probe
  could: the image had *no spatial structure at all*, and **nothing in it exceeded 1.0**. That one
  observation retired the entire "exposure is blowing out" theory that several earlier rounds had
  been built on. It was never a brightness bug.
- **The peak's screen position across frames** — (19,10), (23,2), (12,4), (6,13) — proved the
  artifact was world-anchored rather than screen-locked, which is what turned "a blob" into "a beam"
  and pointed straight at volumetrics.

The instruments are in `lib/diagnostics.zig` and are meant to be deleted once this settles. The
lesson they encode is the one this file keeps relearning, in its sharpest form yet: **reasoning from
a rendered image reliably produces confident wrong answers here, and the cheapest measurement beats
the best hypothesis.**

One instrument was itself wrong and cost a round: the pixel probe — and the in-game G-buffer
inspector alongside it — read `passes[0].bindings`, the flip state *before* anything runs, while the
gbuffers stage writes whichever side `prepare` last wrote. It reported a perfectly black albedo that
was in fact a cleared buffer, producing a false "terrain writes no colour". Both now go through
`gbufferReadBindings`. A debugging tool that lies about the one thing it exists to check is worse
than no tool.

## The lighting session: five wrong frames and one buffer that was never written

Everything from here to "Installing packs" is one long investigation, told once rather than in the
order it was discovered. It is worth reading as a unit because the order was mostly wrong: the
symptom that started it was blamed on the sky, then the fog, then the shade, and was in the end a
depth buffer that had never been rendered into since the mod was written.

The user-visible symptoms were, in their words: a sun that "flips back and forth between in the sky
and in the ground depending on where I'm looking", light that "overlays all blocks and will only ever
go away when I'm in caves", and later direct sunlight that "stops reaching the ground" at particular
view angles.

### The bugs, in one table

| what | was | should have been |
|---|---|---|
| `worldTime` | `DayTime.dayTime` — 12000 units, 0 at noon | Minecraft ticks — 24000, 0 at dawn |
| `far` | the LOD-0 radius, 384 blocks | the LOD-extended render distance, 12288 |
| sky lightmap (`lmcoord.y`) | Cubyz's attenuated sun *intensity* | Minecraft's sky *access* |
| `isDay` | `sunPosition[1]`, a **view-space** height | the world-space sun elevation |
| `skyColor` | `fog.skyColor`, already tinted per channel | `biomeFog.skyColor`, hue-stable |
| `shadowtex1` | allocated, cleared, **never rendered into** | the same depth map as `shadowtex0` |
| translucent depth writes | off, per Cubyz's own pipeline | on, as Minecraft's translucent pass does |
| `cubyz:grass` | matched Minecraft's `grass`, a *plant* | `grass_block`; the plants are `*_vegetation` |

Six of those eight are the same shape: **a value that is supplied, and wrong.** The uniform is
present, plausible, in range, and means something other than what the consumer expects — a different
clock, a different frame, a different unit, a different stage of processing. No GL error, no warning,
no gap in the coverage report. The only thing that finds them is asking what the *consumer* means by
the name.

### `shadowtex1` was never rendered into, so nothing was ever shadowed

The big one, and the reason the others were so hard to see.

`bindShadowFramebuffer` attaches only `shadow[0]`. `shadow[1]` — the pack's `shadowtex1` — sat at its
cleared depth of 1.0 for the entire life of the mod. That reads as *"nothing occludes"*, and packs do
not sample the two symmetrically:

```glsl
float shadow0 = texture(shadowtex0, coord);   // real map: correctly reports OCCLUDED
float shadow  = 1.0;
if (shadow0 < 1.0)                            // so ask whether that occluder was opaque...
    shadow = texture(shadowtex1, coord);      // ...the empty map answers LIT
```

Every sample `shadowtex0` correctly reported as occluded was handed to an empty `shadowtex1` and came
back fully lit. **The volumetric fog was never shadowed anywhere, including inside solid rock** —
that is the sunlit haze that fills cave mouths — and `world0/deferred1.fsh:99` uses
`textureGather(shadowtex1, ...)` as its *primary* occlusion source, so **terrain had no shadow map
contribution either**.

Minecraft's split between the two is by transparency: `shadowtex0` is every caster, `shadowtex1` the
opaque ones only, and the difference tints a shadow cast through stained glass. Cubyz's shadow pass
draws opaque terrain and nothing else, so the two genuinely *are* the same buffer, and binding
`shadow[0]` for both states that. The cleared texture was silently claiming something much stronger.

Measured either side of the fix, same world:

| | before | after |
|---|---|---|
| surface `lit/albedo`, median | 0.112 | **0.352** |
| fog scattering, median | ~0.03 | **0.0003** |

The fog fell a hundredfold once its march was actually shadowed. That accounts for an excess of
10.3x which had been measured against the pack's own constants and left unexplained for several
rounds — the march was integrating fully-lit air along its entire length.

**Why five separate shadow investigations came back clean.** Every one verified `shadowtex0` —
coverage 69%, exact self-occlusion, correct depth band, stable world-space sun — and `shadowtex0` was
right the whole time. Nobody asked what the pack *did* with the answer. The generalisation:
**verifying that a value we supply is correct says nothing about whether the consumer's use of it is
satisfied**, and "the subsystem is healthy" is not the same claim as "the feature works". An
allocated-but-never-written buffer produces no GL error, passes a coverage report, and reads as a
perfectly valid texture.

### `isDay` was read in view space, so the shadow map inverted when you turned

The last symptom standing: direct sunlight cutting out over the whole scene at certain view angles.
One line:

```zig
const isDay = values.sunPosition[1] >= 0;   // sunPosition is in VIEW space
```

`sunPosition[1]` is the sun's height *on screen*, not in the sky. So "is it daytime" was a function
of where the camera pointed. Pitch across the threshold and the bridge concluded it was night,
swapped the shadow light to the moon, negated `lightDirection`, and inverted the entire shadow map —
a whole scene switching between lit and unlit, from a stationary player.

Replaced by `matrix.isDaytime`, which takes **no matrix at all**: there is nothing in it for a view
to get into. Two tests pin it — the answer must be identical across camera pitches from -80 to +80
degrees, and a second asserts the old view-space expression genuinely did flip over that range, so
the diagnosis cannot quietly rot.

### Two suns: `worldTime` was on Cubyz's clock

Nostalgia does not derive its sky from `sunPosition`. It bakes a 256x256 capture in `prepare`, and
`program/deferred/skyboxPrep.vsh` computes the sun that capture is painted around from `worldTime`
alone:

```glsl
float ang = fract(worldTime / 24000.0 - 0.25);
sunDir    = vec3(-sin(ang * tau), cos(ang * tau) * sunRotationData);
```

Everything *else* — `lightDir`, the shadow camera, the volumetrics, the lens flare — comes from
`matrix.celestialWorldDirection`. Two independent chains, sharing no code, agreeing only if
`worldTime` is a genuine Minecraft tick.

It was not. Cubyz's cycle is **12000 units starting at noon**; Minecraft's is **24000 ticks starting
at dawn**. Wrong in rate *and* phase: the painted sun swept half a revolution per day, at half speed,
a quarter-turn out. At Cubyz noon, with the real sun overhead at `(-0.014, 0.906, 0.423)`, the
capture put its sun at `(1.0, 0.006, 0.003)` — flat on the horizon, 90 degrees away. Measured across
one session, the two were 90 to 146 degrees apart; after the fix, 0.0.

`worldTime` reaches much more than the sky, and all of it was equally wrong: `isCloudSunlit` is
`(worldTime > 23000 || worldTime < 12900)`, which on a 12000-tick clock is **permanently true**, so
clouds were lit as if by day at midnight; the seven `clamp(worldTime, a, b)` ramps behind
`fogDensityCoeff` never reached their second half.

The fix and its reasoning are in `lib/worldtime.zig`. Its main test evaluates the pack's own formula
against `celestialWorldDirection` across a full day and asserts they agree, so the two chains are
pinned to each other rather than merely both looking plausible.

**This was not the cause of the reported symptom**, and was briefly declared as the fix on the
strength of an invariant that did not measure it. See the method notes below.

### The sky lightmap was intensity, not access

`world0/deferred1.fsh:381` gates direct sunlight:

```glsl
directSunlight *= sstep(unpack2x8(tex1.z).y, 0.1, 0.2);
```

Any surface whose sky lightmap reads below 0.2 loses its sunlight outright — the shadow map is never
consulted. In Minecraft that guard never fires outdoors, because sky lightmap there means sky
*access* and sits at 15/15 in open shade, dropping only once a surface is genuinely enclosed. Cubyz's
sun light is attenuated *intensity*, so ordinary outdoor shade fell under the threshold and went
black.

Decoding `colortex1.z` from a session showed the gate was the whole story, no exceptions across 32
surfaces:

| sky lightmap | gate | `lit/albedo` |
|---|---|---|
| 0.094-0.102 | **0.000** | 0.0020 |
| 0.114-0.157 | 0.05-0.60 | 0.0054-0.0098 |
| 0.243-0.965 | **1.000** | 0.038-4.68 |

`lmcoord` now saturates at `lightmap.skyAccessFull`, a plateau with a **linear** ramp.

**A first attempt cubed it and made things measurably worse** — see the method notes; the cube
collapsed exactly the band shaded ground occupies, taking a raw 0.2 from 51/255 to 5/255 and a raw
0.05 to exactly 0, so shaded surfaces lost their lightmap entirely and rendered black. There is now a
test asserting the mapping **never returns less than its input**, which is precisely the property
whose absence caused that regression.

Note the two paths deliberately still differ. `eyeBrightness` is a per-frame *classifier* ("is the
player in a cave"), where the plateau-and-cube of `toSkyExposure` is right; `lmcoord` is a per-vertex
value the pack both shades from *and* gates sunlight on. `lightmap.zig`'s header used to assert the
two "describe the same light" — that assertion was the thing that misled.

### `skyColor` was already tinted, so the pack tinted it twice

At dawn and dusk the sky came out **green**.

`game.zig` computes `fog.skyColor = biomeFog.skyColor * getSkyColorFactor()`, and that factor fades
the channels at *different* rates: blue drops first while red and green hold, so it passes through
`(fading, 1, 0)` — pure green. Nostalgia takes `skyColor` as `linearSky` and runs it through its own
`daytimeColor(sunrise, noon, sunset, night)` blend, with a hardcoded colour for night. Handing over
the already-tinted value applied the sunset twice, and the second application landed on Cubyz's green
intermediate.

Minecraft's `skyColor` changes *brightness* with the time of day but holds a stable blue hue; sunset
orange comes from the pack's blend, not from this uniform.

Handing over the raw `biomeFog` colour fixed the hue but flattened the gradient — the zenith then
held full daylight brightness at dusk and never travelled far enough to meet the horizon band, so the
two met in a hard edge. `uniforms.hueStableSky` takes the biome's hue scaled by the strongest
surviving channel of Cubyz's own factor: the strongest specifically because it holds full daylight at
exactly 1.0, where a mean or a luminance would dim noon the moment any single channel began to fall.

### `far` was the LOD-0 radius, so the world ended at 384 blocks

Cubyz is known for its view distance, and the pack was throwing away 97% of it.

`fogDistances().end` is `renderDistance * chunkSize` = 384 blocks — but that is only the **LOD-0**
radius. `mesh_storage.freeOldMeshes` keeps meshes out to `renderDistance * chunkSize << lod` for
every level up to `highestLod`, so the world actually extends 12288 blocks. Using the LOD-0 radius
cost that twice over: it was the pack's projection far plane, so every LOD chunk past 384 blocks was
**clipped**, and `getFog` is `dist/far` against `fogStart` 0.3, so whatever survived was fogged out
from 115 blocks. The horizon sat exactly where full detail ended.

`renderDistanceBlocks()` now feeds both the far plane and the `far` uniform, kept as the same number
because `depthLinear` reconstructs distance from a depth only that projection wrote. `fogStart` and
`fogEnd` deliberately do *not* follow it — they are separate uniforms in Minecraft too, and Cubyz's
fog should still veil the edge of full detail rather than being pushed to the LOD horizon.

**This is a correction to a correction.** `far` was `renderer.zFar` (65536) originally, which spread
fog across the whole numeric range and washed the frame flat; moving it to "the render distance" was
right, and it picked the wrong render distance.

### Water was transparent because translucents wrote no depth

Cubyz builds `transparentPipeline` with `.depthWrite = false`, which is right for its own shader: it
blends layers of transparency against each other and depth writes would let a near surface hide a
farther one. Minecraft's translucent pass writes depth, and packs depend on it having done so,
because the depth difference *is* how the thickness of the water is measured:

```glsl
vec2 sceneDepth  = vec2(texture(depthtex0, uv).x, texture(depthtex1, uv).x);
bool translucent = sceneDepth.x < sceneDepth.y;
```

With no depth written the two are identical, `translucent` is never true, and every effect keyed on
it switches off at once — absorption, refraction and water fog alike. Water rendered as a flat tint
over an undimmed sea bed however deep it was.

`bindWaterUniforms` sets the mask, because it runs *after* `transparentPipeline.bind` — the same
ordering the blend-state replacement already relied on. `endTranslucent` restores it rather than
leaving it for the next `Pipeline.bind`, because the item-drop renderer draws next.

### `cubyz:grass` is a ground block; Minecraft's `grass` is a plant

Soil blocks visibly jiggled, misaligned from the grid.

`program/gbuffer/solid.vsh` wind-displaces exactly ids 10021-10024 and 10027, and Nostalgia lists
`grass` in `block.10022` alongside `fern`, `wheat` and the saplings. In modern Minecraft `grass` is
the *plant* — the ground block is `grass_block`, which this pack never lists. `cubyz:grass` is a full
solid cube (`.model = "cubyz:cube"`), so the ground was being waved as foliage.

Then it spread. `blockids.zig` keys its table by *texture index* and stamps a block's id onto all
sixteen of its textures; `cubyz:grass` declares `.texture_bottom = "cubyz:soil"`, so claiming a
foliage id also stamped the soil texture and every plain soil block in the world inherited the wave.
That is the documented cost of the texture-keyed table showing up for real: **a wrong id does not
stay on one block.**

The inverse held too — Cubyz's actual plants are `*_vegetation`, which matches nothing any pack
declares, so the blocks that *should* wave did not.

`blockmap.minecraftEquivalent` rewrites the path before matching: the `*grass` ground blocks to
`grass_block`, and `*_vegetation` to `grass`. It is an **equivalence, not a suppression** — a pack
that does declare `grass_block` still gets the ground block, and a test asserts exactly that so
nobody later "simplifies" it into a special case returning 0.

## Method notes from that session, which cost more than the fixes

The fixes above are a few dozen lines. Finding them took most of a day and a lot of the user's
patience, and the reasons are worth more than the code.

**Read `logs/latest.log` before forming a hypothesis.** Still the single highest-value rule in this
file.

**A held-still capture beats any amount of reasoning about a screenshot.** The bug that outlasted
everything — the shadow map inverting — was found by asking the user to hold the bad state for ten
seconds, then the good state for ten seconds, so both landed in a log that reports once a second.
Diffing them showed shadow map coverage flipping between 66% and 71% *at a fixed pitch* with frame
brightness inverting alongside, on an unchanged chunk set of 3341 chunks. Same geometry, different
map, so the projection was moving. Every guess before that capture — contact shadows, cloud shadows,
`caveMult`, `diffuseHammon`, the shadow bias — was wrong and cost a launch.

**Log the whole structure, not the summary value.** Even with the capture, `lightDir` read perfectly
stable, because it is row 2 of the shadow basis and a 180 degree flip about the light axis leaves row
2's direction intact while inverting `right` and `up`. Logging the *full* basis made it a one-read
answer: the vector was not drifting, it was negating.

**A correlation assembled by a script is only as good as the script.** One analysis correlated fog
scattering against `vDotL` across two separate parsing passes and produced a beautiful result — every
spike above +0.95, exactly the Mie forward peak. It was wrong. The sun was 35-65 degrees *above* the
horizon while the camera was pitched 50 degrees *down*, which makes that geometrically impossible;
the raw log showed `sunView.z` positive, sun behind the camera. The numbers were real and the join
between them was not. `pitch` and `vDotL` are now emitted on one line from one place. **Measuring
correctly and then joining the measurements up wrongly is a failure mode that "prefer measurement
over reasoning" does not protect against.**

**An invariant only closes a bug if it is one the symptom would have violated.** The `worldTime` fix
was declared as *the* fix on the strength of `angle=0.0 deg` between the two suns. That measurement
was real, correct, and about something else entirely. The user caught it.

**A fix shipped mid-investigation becomes part of the system under test.** The cubed `lmcoord`
regression made shaded ground render black, and three subsequent rounds of measurement were spent
analysing that as if it were evidence about Cubyz's light data. Nothing in the logs could separate
"the engine has no light here" from "we just deleted it" — only toggling the pack off could, because
it was the one test that did not run through the changed code.

**Check the instrument before trusting it — three of them lied this session.** A CPU probe sampled
*past* the surface, inside the solid block where light is always zero, and reported a confident
`(0,0,0)` everywhere. An exposure probe re-attached a colortex after `swapFlippedBuffers` had
deliberately detached it, so once a second the next frame began with a foreign texture bound — which
rendered as a flicker, and violated this file's own promise that the diagnostics change nothing. And
a distance probe linearised depth with `renderer.zFar` while the pack's geometry was drawn with a far
plane of 384, over-reporting by 19%. **A probe that reconstructs a world position from depth and a
look vector has many ways to land on the wrong block, and none of them announce themselves.**

**When a symptom is view-dependent, suspect anything that reads a view-space value to answer a
world-space question.** That is `isDay` exactly, and it is the sharpest single heuristic this session
produced.

**When a fix does not change the symptom at all, treat it as an elimination.** Contact shadows, cloud
shadows and a `lodDistance` cull were each tried and each changed nothing; recording them as
eliminations is cheaper than someone re-deriving them.

### Still wrong

- **`toSkyExposure`'s cubic makes `caveMult` hypersensitive.** Eye-block sun light of 185 gives 1.0,
  150 gives 0.47, 120 gives 0.18 — the same cliff already removed from the `lmcoord` path. It affects
  only the volumetric fog's sunlight, so it would show as fog brightness jumping as the player moves.
  Not observed as a symptom, but it is the same mistake still in place on the other path.
- **`lib/diagnostics.zig` is now gated rather than deleted.** It is off unless
  `settings.shaderDiagnostics` is set — `Settings -> Shaders -> Log diagnostics`, read per frame, so
  it toggles live in both directions. The gate is one `if(!enabled())` per entry point rather than a
  check at the call sites, so a probe added later cannot be the one that misses it.

  Deleting was the other option and the case for it is weaker than it looks. Its cost was real —
  a reporting frame spent over a hundred synchronous readbacks and the driver said so in the log,
  `Pixel transfer is synchronized with 3D rendering`, with 3715 of one run's 6747 lines being
  `irisbridge/diag` — but that cost is a *frequency*, and gating removes it entirely. What deleting
  would remove is the part worth keeping: every new pack in this project's history has exposed a
  systemic defect, five times out of five, and these are the instruments that found them. Most of the
  method notes above are a record of what each one had to learn to stop lying. Rebuilding that costs
  a session; leaving it switched on costs every frame; gating costs a boolean.
- **Depth writes on translucents may affect other transparent blocks.** Glass and anything else in
  Cubyz's transparent set now occlude rather than blend where they overlap. Minecraft behaves the
  same way so packs expect it, but Cubyz's transparent set is not Minecraft's; if glass looks wrong,
  this is why, and it can be narrowed to the water program only.
- No entity, particle or item-drop gbuffers programs — those still draw through Cubyz's own shaders.
  They land in whatever colortex the terrain pass attached, with Cubyz shading, and contribute
  nothing to the material buffers, so a deferred pass lights them a second time.

  **An earlier version of this bullet said they light "using whatever normals happened to be behind
  them". That was wrong, and the way it was wrong cost a visible bug** — see "A single-output shader
  in a four-attachment framebuffer" below. Unwritten attachments are *undefined*, not preserved.

  Feasible, and the shape is known: `entity_vertex.vert` has conventional attributes (`inPos`,
  `inNormal`, `inUV` plus a packed `light` uniform), which map onto the Minecraft vertex set far more
  directly than the chunk SSBO pull did. Two things make it more than a prologue variant, and both
  are worth knowing before starting: the sampler redirect must **not** fire for entities, because
  `gtexture` there is a genuine 2D texture rather than Cubyz's block array, so the transformer needs
  a per-program sampler policy; and particles, item drops and block entities each have their own
  vertex path, so it is four prologues rather than one.

## What Kappa found

Kappa v5.3 (RRe36) is the fourth fixture pack, and it produced two symptoms in its first session.
Both were located by reading — the pack's own source and `logs/latest.log` — with no launch spent on
a hypothesis.

### A single-output shader in a four-attachment framebuffer

The symptom: selecting a block put a **glowing white blob** on the screen several times the size of
the block, with the selection cube's own wireframe visible inside it.

Kappa's `gbuffers_terrain` declares `/* RENDERTARGETS: 0,1,2,4 */` — albedo, two packed material
buffers and geometry normals. Cubyz's block-selection outline draws *inside* the geometry stage
(`renderer.zig`, between the opaque chunk draw and the translucent one), so those four attachments
are bound, and `assets/cubyz/shaders/block_selection_fragment.frag` is one output:

```glsl
layout(location = 0) out vec4 fragColor;
void main() { fragColor = vec4(0, 0, 0, 1); }
```

**GL leaves every attachment a fragment shader does not write undefined — not untouched.** So the
outline wrote black into albedo and garbage into colortex1, colortex2 and colortex4, the deferred
chain decoded that garbage as material and normals, lit it, and `composite10`-`composite14` bloomed
the result outward. The wireframe survives inside the blob because those are the texels that were
actually written.

`beginCubyzShadedDraws`/`endCubyzShadedDraws` narrow the draw buffer list to the albedo target while
Cubyz's own shaders draw. Outputs the list does not map are discarded rather than written, so the
material buffers keep what `gbuffers_terrain` put there. The same pair wraps entities, item drops,
block entities, particles and the held item, which all have the identical one-output shape.

**This was a real defect and it was not the cause of the glow.** Shipped as a fix, measured
afterwards, symptom unchanged — an elimination. The next section is what it actually was. Kept
because undefined writes into a pack's material buffers are wrong on their own terms, but it is
worth being blunt that it was guessed from a mechanism rather than from a measurement, and the
mechanism was real and irrelevant.

Worth recording separately: this file had already described the gap, and described it *wrongly*, as
entities being lit "using whatever normals happened to be behind them". Unwritten attachments are
undefined, not preserved. **A known limitation written down imprecisely is worse than one written
down as an open question**, because nobody re-derives it.

### The glowing selection box was local auto-exposure reading black

The symptom: selecting a block put a soft white blob on screen several times its size, with the
selection cube's own outline visible inside it.

Four rounds of reasoning produced four wrong answers — undefined material writes, a stale ping-pong
side, bloom, and a runaway temporal feedback — and every one of them was killed by the same
instrument, the per-pass crosshair trace in `runPostChain`. Extended to log *every* buffer a pass
writes rather than only the albedo, it produced this:

    after composite9      = (0.0533, 0.1111, 0.0910)     ordinary dark green
    composite14 -> tex3   = (0.0029, 0.0032, 0.0038)     bloom is ~zero
    after composite15     = (0.9321, 0.9238, 0.9233)     white, hue gone

with the frame's mean luminance unchanged at 0.33. So the grading pass was adding a large term that
was **localised**, with no bloom contribution and a perfectly normal input. That is a very short list
of possibilities, and reading `program/grade/grading.fsh` closed it immediately.

Kappa enables `LOCAL_EXPOSURE` in `settings.glsl` by default, which makes exposure a **per-pixel**
quantity sampled from a tiled luminance downsample of the lit frame:

```glsl
float TiledLuminance = SampleExposureTilesSmooth(uv);
float targetExp      = cal / (a - b * exp(-TiledLuminance / b));
```

As `TiledLuminance` goes to zero, `exp(0)` is 1 and that collapses to `cal/(a - b)` — which is
exactly `maxExposure`, the brightest the clamp allows. **A dark patch does not merely brighten, it
saturates the exposure for its whole tile.**

Cubyz's `block_selection_fragment.frag` writes `vec4(0, 0, 0, 1)`. Black albedo lights to black, the
black drags its exposure tile to the floor, the tile is multiplied by the maximum exposure and clips
to neutral white — which is why the measured output is grey rather than green, and why the blob is
far larger than the cube and has soft edges: the tiles are large and sampled smoothed.

`MeshSelection.render` now draws **after** the pack's post chain, straight onto the finished frame,
so it takes no part in any pack calculation.

That needs the scene's depth to be present, and it is not: the default framebuffer's depth is cleared
every frame and Cubyz's deferred pass is `depthTest = false`. **The first version of this shipped
without restoring it, on the reasoning that the only loss was occlusion by geometry in front of the
selected block — "nearly nothing, since the selected block is the first solid block along the view
ray".** That reasoning is true and it missed the case that matters: the cube occludes *itself*. With
every edge passing, all twelve draw, including the six inside the block, and the result reads as an
X-ray wireframe rather than a selection box.

`pipeline.DepthRestore` stamps the pack's `depthtex0` back into the default framebuffer with a
fullscreen pass writing `gl_FragDepth`. A `glBlitFramebuffer` of `GL_DEPTH_BUFFER_BIT` is the obvious
route and is unavailable: depth blits require matching formats, and the pack's depth is
`DEPTH_COMPONENT32F` against the window's 24-bit buffer.

The depth was written with the *pack's* projection while the outline draws with Cubyz's, and their
far planes differ (12288 against 65536). That is safe rather than merely convenient: for
`far >> near` the normalised depth of a near surface is `1 - 2*near/distance` to a very good
approximation and barely depends on the far plane. At five blocks the two conventions differ by about
2e-5 where one block of separation is 6.7e-3 — two orders of magnitude more, so the occlusion
decision is never close.

The proper fix remains Minecraft's: `gbuffers_basic`/`gbuffers_line` at render stage OUTLINE, which
Kappa ships as `program/gbuffer/line.glsl` and which writes all four targets with a material the
deferred chain recognises.

Two method notes, both expensive:

- **Four fixes were shipped before the cause was found, and each became part of the system under
  test.** The file already warned about this. The warning did not stop it happening.
- **"A value that is supplied, and wrong" has a sibling: a value that is supplied, correct, and
  *read by something that treats its darkness as a signal*.** Nothing about the black outline was
  wrong. Cubyz has drawn it that way forever and it is right on its own terms. It only became a bug
  when handed to a consumer that infers exposure from luminance — and no coverage report, GL error
  or uniform audit can see that, because there is no wrong value anywhere in the chain.

### `at_tangent` was an edge, not a texture direction

Kappa's water showed a hard crease across the surface that **followed the camera**. That one word
split the search in half before any code was read: the wave height is a function of `worldPos`, so a
world-anchored seam would have meant the position or the `mc_Entity` table, while a camera-anchored
one can only come from the view-space chain — the tangent frame.

`at_tangent` in Minecraft is the direction of increasing texture **U**, and its `.w` is the frame's
handedness. The prologue was supplying `corners[1] - corners[0]` — an arbitrary edge — with `.w`
hardcoded to `1.0`. That is correct exactly when the first edge happens to run along U and the frame
happens to be right-handed, and silently rotated or mirrored otherwise.

Nothing surfaced it until a pack marched *through* the frame rather than merely sampling with it:

```glsl
vec3 viewBinormal = normalize(gl_NormalMatrix*cross(at_tangent.xyz, gl_Normal.xyz) * at_tangent.w);
...
vec3 interval = inversesqrt(float(steps)) * dir / -dir.y;   // waterParallax
```

The bitangent is *rebuilt* from the tangent, the normal and `.w`, and the parallax march divides by
the frame's normal component. A rotated or mirrored frame puts a sign change in that divisor, and the
surface folds along the line where it crosses — which moves with the view, because the divisor is a
view direction.

Cubyz's quads carry corner positions **and** corner UVs, so the real tangent is derivable by the
standard construction rather than approximated, and `.w` comes from comparing the reconstructed
bitangent against the one the UVs imply. The `voxelSize` scaling cancels in the ratio, so LOD quads
need no special case; a UV-degenerate quad falls back to the old edge tangent rather than to NaN.

Worth stating as its own lesson: **an input can be wrong by definition and still look fine for
months.** Every pack up to this one used `at_tangent` only to orient a normal map, where a rotated
frame is a subtle shading error nobody attributes to the tangent. It took a pack that *divides* by
the frame to turn it into a visible hard edge.

### `ResolutionScale`, again

The symptom: the pack rendered into a rectangle in the bottom-left of the screen, with Cubyz's own
image around it.

This is the same feature that made Nostalgia's textures look blurry and misaligned, and it is worth
recording that it presented completely differently in a second pack. Kappa's source defaults
`ResolutionScale` to 0.75 (`lib/internal.glsl`), and `program/gbuffer/solid.vsh` calls
`VertexDownscaling(gl_Position)`:

    return Position * ResolutionScale - (1-ResolutionScale);

which maps clip space to `[-1, 0.5]` — the bottom-left 75% of every buffer. Every deferred and
composite pass that does **not** `#define FULLRES_PASS` before including `vertexSimple.vsh` draws
only over that sub-rectangle. Grepping `FULLRES_PASS` is what makes the pipeline legible: in
`world0` only `deferred`, `deferred1`, `deferred3`, `composite1`, `composite5`, `composite6`-`9` and
`final` run at full resolution, and **`composite5` is `program/post/temporal.fsh`** — the TAAU
resolve that upscales the low-resolution render back to the screen.

So the sub-rectangle is by design up to `composite5`; what does not happen here is that resolve
filling the screen. Around it sits Cubyz's own render, because Kappa's `prepare` passes write
colortex5, 3, 7 and 11 and never colortex0 — so `flip.writtenTargets` does not contain the albedo
target, `beginTerrain` imports Cubyz's sky into it at full size, and everything outside the
downscaled region is still that import.

`ResolutionScale = 1.0` in `shaderpacks/Kappa_v5.3.options.txt` turns the whole feature into an
identity: `ViewProjectionDownscaling` returns its input and every `uv * ResolutionScale` is a no-op.
Whether Kappa's TAAU resolve *could* be made to work under this bridge is a separate question and is
untouched — it depends on `taaOffset`, `depthtex1`/`depthtex2` and the history buffers all being
right at once, and nothing here has measured that.

The generalisation, since this is now twice: **a pack's own resolution-scaling feature is not a
quality setting the host can ignore.** It changes where geometry lands in every buffer, and the pack
assumes a resolve pass will undo it. Reading the pack's default for it is worth doing on any new
pack, before looking at the image.

## What Complementary found

The fourth pack, and the first by a different author. Everything it turned up was a place where this
bridge had implemented *most* of a rule — enough for two packs by RRe36 to look right, and not enough
to be correct. That is the conformance harness's argument arriving in full.

**Draw-buffer directives: the last one wins.** Covered above. Cost: the pack's normals.

**Shadow samplers are per sampler, and the driver knows better than the source.** Complementary
declares `shadowtex0` both ways behind `#ifdef COMPOSITE1` and `shadowtex1` always as
`sampler2DShadow`. The old code scanned the source text — which sees both branches and cannot know
which survives — then OR-ed the two names into a single flag and bound one sampler object to *both*
units. A pack wanting comparison on one and raw depth on the other could not be expressed at all,
which is the common case rather than an exotic one.

The driver said so, 897 times in one run:

    The current GL state uses a sampler that has depth comparisons enabled, with a texture object
    with a depth format, by a shader that samples it with a non-shadow sampler.
    This will result in undefined behavior

`pipeline.resolveShadowComparison` now asks the linked program with `glGetActiveUniform`, which is
the driver's answer *after* preprocessing and therefore not a guess. The text-scanning helper was
deleted rather than left unused, because it cannot answer the question and leaving it invites
someone to reach for it again.

Worth noting as method: **this file used to claim zero GL errors across every run, and treated that
as evidence of health.** It was evidence of two packs by one author not exercising the gap. A clean
GL log is a weak signal; a dirty one is a very strong one, and this is the first time the driver has
simply handed over a bug.

**`size.buffer` accepts fractions of the screen, and its value may be a macro.** Complementary asks
for its reflection buffers at half resolution:

    #define REFLECTION_RES 0.5          //[1.0 0.5]
    size.buffer.colortex1 = REFLECTION_RES REFLECTION_RES

Two things defeated the parser at once. The value is a `#define`d name rather than a literal — Iris
resolves it because it preprocesses `shaders.properties` against the pack's option values — and even
expanded, `parseInt("0.5")` fails. Both failures were silent `continue`s, so the buffers were
allocated at full screen while the pack addressed them as half, and everything downstream read the
wrong region.

Iris's rule is per axis, from `TextureScaleOverride`: **a value containing a `.` is a fraction of the
screen**, anything else is absolute pixels. `pack.BufferAxis` carries that distinction and resolves
it in `updateSize` rather than at load, because a fractional buffer has to follow the window across a
resize.

This is the same bug as the Nostalgia sky capture — a buffer whose real size disagrees with the size
the pack does its maths in — and this file already recorded that one. It came back because the fix
implemented the *literal* form of the directive and stopped there, and nothing in the code or in this
file said the other form existed. **A partially implemented directive reads exactly like a finished
one.**

The measurement that found it is worth keeping too: a 40x20 luminance map of the finished frame
showed content stopping at exactly column 20 of 40 and row 10 of 20, and the same map of *colortex0*
showed it full. Half in both axes, present after the gbuffers stage and gone by the end of the chain
— which named a factor of two in the composite chain and nothing else. `captureTargetThumbnail`
exists for that question, because a centre-pixel probe structurally cannot answer it: the question is
about *where* content exists, and one texel has no shape.

## What photon found: the width of a synthesised attribute is the pack's choice

photon v1.3b and Sundial Lite v1.1.0 are the fifth and sixth packs, and the first two by authors
whose conventions this bridge had never seen. photon loads — 54 programs, 23 passes — with **four**
programs failing to compile. The first of them is the one worth writing down, because the bridge was
wrong rather than the pack.

`mc_Entity`, `mc_midTexCoord` and `at_tangent` are **pack-declared names, not `gl_` built-ins.** The
pack writes its own `attribute` declaration and picks the width; the prologue synthesises them as
computed globals and `glsl.markStrippedDeclarations` deletes the pack's declaration so the two do not
collide. The prologue declared all three as `vec4` — which is exactly what the four packs it grew up
against write, and what nothing had ever contradicted.

photon writes:

    program/gbuffers_all_translucent.vsh:42    attribute vec2 mc_midTexCoord;
    …:156    vec2 uv_minus_mid = uv - mc_midTexCoord;
    …:157    atlas_tile_offset = min(uv, mc_midTexCoord - uv_minus_mid);

GLSL has no implicit narrowing, so with the declaration replaced by a `vec4` those two lines are
`vec2` mixed with `vec4`, and the driver says so — twice, on adjacent lines:

    gbuffers_water (vert) failed to compile:
    0(3195) : error C7011: implicit cast from "vec4" to "vec2"
    0(3196) : error C7011: implicit cast from "vec4" to "vec2"

The corpus is genuinely split, and the split falls exactly along "packs this bridge was built
against" versus "packs added afterwards":

| attribute | `vec2` | `vec3` | `vec4` |
|---|---|---|---|
| `mc_Entity` | 2 | 3 | 28 |
| `mc_midTexCoord` | 5 | — | 23 |
| `at_tangent` | — | — | 25 |

`prologue.AttributeTypes` now reads the widths back out of the pack's own include-resolved vertex
source and the prologue follows them, in both the terrain and the sky variant. The value is still
computed as the same full `vec4` it always was; only the hand-over narrows, by a swizzle
(`.xyz`/`.xy`/`.x`), so a pack that declares `vec4` gets byte-for-byte the source it got before.

Three things about it are deliberate:

- **The lookup shares its matcher with the stripper** (`glsl.matchDeclaration`). The prologue declares
  a replacement for precisely the declarations the stripper deletes, so a form the two disagreed
  about would leave either a duplicate declaration or a replacement at the wrong width — and neither
  is visible until a driver rejects generated source that exists nowhere on disk.
- **A name the pack never declares keeps `vec4`.** Nothing reads it in that case, and the widest type
  is what every other pack expects.
- **The load logs the resolved widths** when they are not the default. This fix is invisible in the
  image by construction — the program either compiles or it does not — so without a line saying what
  was resolved, "the fix worked" and "the fix did nothing" look identical. This file has recorded
  that lesson twice already and it applies with full force here.

Tests pin the property rather than the strings: for every width, the width a name is *declared* at
and the width the value *assigned* to it is narrowed to must agree. That is the thing that can drift.
`prologue.zig` had no tests at all before this and now has five, which also meant adding it to
`tests.zig` — it turns out to import cleanly under the test stub, because Zig's lazy analysis never
reaches the GL-dependent declarations in `blockids.zig` and `targets.zig`.

**The first test to cover `skyVertex` failed for an unrelated reason worth keeping.**
`test/main_stub.zig`'s `ListManaged.print` formatted into a fixed `[1024]u8` and `catch unreachable`d
the overflow, while the engine's real `List.print` grows without limit. The sky prologue emits a
~1.8 KB block in one call, so the stub panicked with `NoSpaceLeft` on code the engine runs happily
every load. That is exactly the divergence the stub's own header comment says a stub exists to
avoid — a stub that fails where the real type succeeds — and it had been latent since the stub was
written, waiting for the first test to emit more than a kilobyte. It now mirrors the real
implementation.

**Measured in game afterwards, and the failure moved rather than vanished** — which is what
distinguishes a fix from a no-op here. `gbuffers_water`'s *vertex* stage went from two
`implicit cast from "vec4" to "vec2"` errors to compiling, and its *fragment* stage — never reached
before — now reports the next problem along. `gbuffers_terrain` is byte-for-byte the same failure at
the same line, correctly, because it was never a width problem.

The other three photon failures are still open, and the two gbuffers ones turn out to be the same
subsystem seen from opposite sides. photon wraps every texture read in a macro of its own:

    #define read_tex(x) textureGrad(x, parallax_uv, uv_gradient[0], uv_gradient[1])   // POM
    #define read_tex(x) texture(x, uv, lod_bias)                                      // otherwise

- `gbuffers_water` calls `textureGrad` longhand in its parallax loop, so the redirect **fired
  correctly** and produced `cubyz_sampleArray(sampler2DArray, vec2, vec2, vec2)` — a signature the
  prologue never declared. `textureGrad`/`texture2DGrad` were in `samplingFunctions` while
  `terrainFragment` only overloaded `(s, vec2)`, `(s, vec2, float)`, `(s, vec2, int)` and `(s, vec3)`.
  **Fixed**, and fixing it turned up a second bug that had nothing to do with photon.

  **`texture(s, c, x)` and `textureLod(s, c, x)` are the same argument shape and different
  meanings** — a bias applied to the implicitly computed level of detail, against an explicit level.
  Both were redirected onto the single name `cubyz_sampleArray`, which could only carry one body, and
  the body it carried was the bias one. So **every `textureLod` on the block texture silently sampled
  with a bias instead of at the level the pack asked for.** A wrong mip level, no error, no warning,
  and nothing in the coverage report — the sampler is supplied, the call compiles, the value is
  plausible. It is the same shape as the rest of this file's recurring bug, one level down: not a
  uniform that is supplied and wrong, but a *call* that is redirected and wrong.

  `SamplerRedirect` now carries three helpers rather than one — `function`, `lodFunction`,
  `gradFunction` — and `glsl.Flavour` records which built-in a call site used, so the distinction is
  made once where it is known rather than guessed from arity later. `specular` names the same helper
  three times, legitimately: its value is synthesised, so a level and a derivative have nothing to
  select. A test asserts that **every helper any redirect can name is actually declared by the
  prologue**, which is the invariant photon's failure violated.
- `gbuffers_terrain` writes `read_tex(gtexture)`. `markArraySamplerCalls` scans tokens, sees a call to
  `read_tex`, and correctly does nothing; the **driver** then expands the macro and
  `#define gtexture cubyz_blockTextures` leaves `texture(sampler2DArray, vec2, float)`. **The
  per-call-site redirect cannot see through a pack's own macro, because this transformer does not
  preprocess.**

### Dispatching a sampler by type, because its name is not knowable

The macro case is not a photon quirk. **Three of the six packs wrap every texture read this way**, by
two different authors and under two different names:

    Kappa, Nostalgia   #define stex(x) texture(x, uv)
                       #define stexLod(x, lod) textureLod(x, uv, lod)
    photon             #define read_tex(x) texture(x, uv, lod_bias)
                       #define read_tex(x) textureGrad(x, parallax_uv, uv_gradient[0], uv_gradient[1])

Neither end of it can be handled by name. At the call site the callee is `read_tex`, and rewriting it
would destroy the macro's argument list. Inside the body the sampler is `x`, which names no
particular sampler — photon invokes the same macro with `gtexture`, `normals` and `specular`.

So the *body* is redirected to `cubyz_sampleAny`, which is **overloaded on sampler type**, and the
compiler resolves it per expansion — after preprocessing, which is exactly where the token scan
cannot reach. The `sampler2DArray` overload performs Cubyz's array lookup; the `sampler2D` overload
is an exact passthrough, so a macro invoked with an ordinary 2D sampler behaves precisely as before.

**Overloading the built-in `texture` itself would have been simpler, and it does not work.** That was
measured rather than argued, with a throwaway probe compiled by the driver at load:

    0(13) : error C1102: incompatible type for parameter #1 ("s.1")
    0(14) : error C7011: implicit cast from "vec3" to "vec2"

The *declaration* `vec4 texture(sampler2DArray, vec2)` is accepted. What follows is that **every
built-in overload of that name is hidden** — line 13 is an ordinary `texture(sampler2D, vec2)` and
line 14 an ordinary `texture(sampler2DArray, vec3)`, and both stop resolving. Shipping it would have
taken all four working packs down at once. The probe is deleted now that it has answered; the answer
is in "Do not re-litigate these".

Two things about the scope are deliberate:

- **Only gbuffers fragment stages get the dispatch.** The helpers live in the terrain fragment
  prologue, and Kappa and Nostalgia use `stex` throughout their *deferred and composite* programs
  with ordinary colortex samplers. Those passes have no prologue, so rewriting there would break four
  working packs to fix one. `macroDispatch` is null everywhere else and a test pins it.
- **The per-sampler redirect still wins where a call names its sampler outright.** The dispatch is a
  fallback for what cannot be named, not a replacement.

The cost, stated up front rather than discovered later: `read_tex(specular)` resolves to the plain 2D
passthrough rather than to `cubyz_sampleSpecular`, so a pack reading its material maps *through a
macro* gets the neutral 1x1 texture instead of the LabPBR value synthesised from Cubyz's emission and
reflectivity. Distinguishing them needs the *type* of the macro's argument, which is inference across
a call graph — the same wall `textureAF` sits behind under "Known limits". A pack that reads its
material maps directly is unaffected.

`composite3` reports an `unmatched #endif`, which is generated source being malformed and so points at
`#include` resolution or the option line-rewrite rather than at the pack. `composite2` hits the pack's
own `#error "This program should be disabled if Depth of Field is disabled"`; see the handoff's open
items for why `program.<name>.enabled` misses it twice over.

## What Sundial Lite found, before it was ever launched

Sundial Lite v1.1.0 is the sixth pack, and everything below was found by reading it and the archived
log of its one previous load — no launch was spent on any of it. Both defects are the shape this file
keeps recording, and neither is Sundial-specific in kind.

### `alphaTestRef` was never supplied, so nothing was ever cut out

The coverage report listed it among 32 names nothing supplies, in a run where it was buried between
`physics_*` (the Physics Mod's ocean) and `dh*` (Distant Horizons) — both of which Iris does not
supply either. Checking each against Iris rather than eyeballing the list is what separated them:
`IrisInternalUniforms:53` supplies `alphaTestRef` outright, commented **"Optifine compatibility"**.

The consequence is not a subtly wrong value. GL hands an unbound uniform **zero**, and the pack's own
cutout is

    if (albedoData.w < alphaTestRef) discard;      // Sundial, programs/gbuffers/Terrain.frag:82

which at zero **never fires**. Cubyz's own `chunk_fragment.frag` discards on alpha too
(`passDitherTest`), so with the pack's program substituted this is the only thing doing the job.

The alpha content of Cubyz's textures was measured rather than assumed, and it decides the numbers:

| | measured |
|---|---|
| opaque albedo | **strictly binary** — every texel 0 or 255 across all 665 textures |
| textures carrying fully transparent texels | **232 of 665**; leaves run 27-76% transparent |
| textures carrying *partial* alpha | **5**, and all five are `.transparent = true` |
| those five | water **0.42**, resin 0.55, ice 0.64, amber 0.60 and 0.71 |

So every leaf block was rendering as a solid cube, and the threshold is taken per stage from Iris's
own `ShaderKey` table:

- **Opaque terrain — `TERRAIN_CUTOUT`, 0.5.** Minecraft splits solid (test off) from cutout where
  Cubyz has one draw carrying both, and it is the *cutout* pass this stands in for. Because the
  opaque set is strictly binary, any threshold in `(0, 1)` behaves identically, so following Iris
  costs nothing.
- **Translucent — `TERRAIN_TRANSLUCENT`, 0.0001.** The one place the number is load-bearing: at the
  opaque threshold, Cubyz's 0.42-alpha water and 0.55 resin would be **discarded outright**.
- **Shadow — `SHADOW_TERRAIN_CUTOUT`, 0.1.** Otherwise a leaf casts a solid cube's shadow.

**The corpus survey is worth stating precisely, because it cuts the other way for once.** Two packs
declare the uniform, not one — but Kappa reads it only inside `#ifdef pomEnabled`, and its own source
ships `//#define pomEnabled` with the options file leaving it alone, so its live path uses a
hardcoded `a < 0.1`. Kappa is *declared* affected and *not* live. Saying "two of six packs" would
have oversold it; the honest claim is that one pack is broken by this today and a second is one
option away.

### `block.properties` was preprocessed after its continuations were joined

Sundial continues twelve of its `block.` entries across conditionals:

    block.8192 = \
    #if MC_VERSION < 11300
                 flowing_water \
    #endif
    #ifdef IRIS_TAG_SUPPORT
                 %minecraft:water \
    #endif
                 water

`blockmap.parse` called `joinContinuations` **first**. That pulls every `#if` into the middle of a
value, where `run` — which only recognises a directive at the start of a line — cannot see it. The id
then collected `#if`, `MC_VERSION`, `11300`, `#endif`, `IRIS_TAG_SUPPORT` **and both branches' block
names**, which is exactly the failure `parse`'s own header already warned about: a legacy `#else`
branch *redeclares* the same keys rather than adding to them. 67 directives were swallowed this way
across 12 of Sundial's 33 entries.

Iris arrives at the opposite order by a route worth reading, because it is not guessable.
`PropertiesPreprocessor.process` rewrites every `\` to `IRIS_PASSTHROUGHBACKSLASH` before handing the
text to its C preprocessor and restores them afterwards — the code's own comment is *"trick the
preprocessor into not seeing the backslashes during processing"* — so directives are evaluated while
continuations are still intact and `Properties.load` joins them last. `BACKSLASH_MATCHER` names
`block\.\d*` explicitly for the same reason.

The fix is the call order plus one rule: **a blank line does not close an open continuation.** No
properties author writes one, but it is exactly what `run` leaves where it removed a branch, so
without it the join ends on the first line the preprocessor took out. `shaders.properties` already
had the right order (`load` runs `preprocess.run` before `parseProperties`), which is what made the
disagreement between the two paths the tell.

Two tests pin it, in **both** directions — the wrong order must still be demonstrably wrong, or the
right-order test would keep passing while measuring nothing.

## Two defects found by reading, with no symptom to go on

Neither had an observable symptom, which is the point: both are cases where the code was one step
from being right and nothing in the image would ever have said so.

**The world import was landing on the pre-`prepare` side.** `runPostChain` passed
`state.passes[0].bindings` to `importWorld` — the flip sequence *before* anything has run — where
that blit stands in for the whole gbuffers stage and so must use the side the last `prepare` wrote.
Reachable only when `terrainPass == null`, the degraded path a pack lands in when its terrain program
fails, and `gbufferReadBindings` shared the same fallback — so the G-buffer inspector lied in exactly
the state where it is most needed. This is the *third* appearance of `passes[0].bindings`; the
resolved gbuffers bindings are now a field on the pipeline, present whether or not a terrain program
compiled, so there is nothing left to fall back to.

**The shadow pass substituted half a matrix set.** `bindShadowUniforms` overwrote
`gbufferModelView`/`gbufferProjection` with the shadow pair and left the inverses on the camera, so a
pack reading both got two matrices that do not compose to identity.

**The obvious fix — substitute the inverses too — is the wrong direction, and Iris says so in one
line.** `MatrixUniforms.addMatrix` registers `gbufferModelView`, its `Inverse` and its `Previous`
against `CapturedRenderingState::getGbufferModelView` at `PER_FRAME`, and nothing swaps that supplier
while the shadow map renders: **`gbuffer*` is the camera's in every program.** What moves to the
light is the *compat* set — `ExtendedShader` sets `iris_ProjMatInverse` from
`areShadowsCurrentlyBeingRendered() ? ShadowRenderer.PROJECTION : getGbufferProjection()` and derives
`iris_ModelViewMatInverse` and `iris_NormalMat` from whatever model-view is current.

The corpus agrees on both halves at once:

| pack | reads, in its shadow program | means |
|---|---|---|
| Complementary | `shadowModelViewInverse * shadowProjectionInverse * ftransform()` | `gl_ProjectionMatrix * gl_ModelViewMatrix` **must** be the shadow pair |
| photon, Kappa, Sundial | `shadowModelViewInverse` applied to `gl_ModelViewMatrix * vertex` | the same |
| Kappa | `length(transMAD(gbufferModelView, scenePos))` to LOD its parallax | distance from the **camera** |
| photon | `get_voxel_volume_center(gbufferModelViewInverse[2].xyz)` | the **camera's** look direction |

So substituting the inverses would have aimed photon's light-propagation volume at the sun. Nothing
showed the original defect because `matrix.shadowModelView` and `gbufferModelView` are both pure
rotations and both of those uses happen to be rotation-invariant — an accident, and one that stops
being one on the next pack.

## Four things found by reading rather than by running

No launch was spent on any of these. Each is an instance of a pattern this file already names, which
is the argument for the patterns being written down.

**`screenBrightness` was 1.0, the top of its range.** Iris supplies it from Minecraft's brightness
slider, whose default is **0.5**. Cubyz has no brightness setting at all, so this is a documented
constant like `rainStrength` — but it was missing from `unsupported`, and because it is a `Values`
field the coverage report counted it as supplied. **Invisible to both mechanisms that exist to catch
exactly this.** Packs treat it as an ordinary player setting and scale real lighting by it:
Complementary reads it sixteen times through `vsBrightness`, where 1.0 against 0.5 raises its
minimum-lighting floor from 0.027 to 0.049, night ambient from 1.935 to 2.32, volumetric light by a
third, and moves `composite3`'s focus term `pow2(vsBrightness)` from 0.25 to 1.0. Now 0.5, and listed
in `unsupported` so it stays visible.

This is the fifth instance of **a value that is supplied, and wrong** — and the first found by asking
the inverse question to the coverage report's. That report asks "what does the pack want that nobody
supplies". The question that found this one is "which `Values` fields does `capture` never assign,
and is each of those in `unsupported`?" Every field failing that check is a constant nobody has
justified. It found one real defect and cleared the rest: `renderStage` is set per draw, `entityColor`
and `pi` and `seaLevel` are correct by construction, and `ambientLight` is genuinely 0 — Iris sources
it from `dimensionType().ambientLight()`, which is 0 for anything overworld-like.

**Both smoothed uniforms faded at a rate set by the frame rate.** `eyeBrightnessSmooth` and
`centerDepthSmooth` used a fixed coefficient per *frame*, so the fade they promise — a duration —
varied with how fast the machine ran: the same 0.95 is a third of a second at 60 fps and a tenth at
200. `eyeBrightnessSmooth` is what gates Nostalgia's `caveMult`, so the cave-fog transition took six
times longer to settle on a slow machine than a fast one, and nothing said so, because at any single
frame rate it looks like a working fade. Iris uses a half-life for this reason. `lib/smoothing.zig`
now does `1 - exp(-dt/tau)`, with both time constants chosen to reproduce the old coefficients at 60
fps — the point is to remove the frame-rate dependence, not to quietly retune two fades. Five tests
pin it, including one asserting the old fixed coefficient genuinely did diverge, so the diagnosis
cannot rot.

**The depth inspector linearised with the wrong far plane.** `Settings -> Shaders -> Show G-buffer`
reads a depth texture back through `(2·near·far)/(far + near - ndc·(far - near))` and was handed
`renderer.zFar` (65536), while the depth in it was written by the pack's projection at
`renderDistanceBlocks()` (12288). It over-reported every distance by 5.3x. This project has already
paid for this exact mistake: the method notes record a distance probe linearising with `renderer.zFar`
against geometry drawn to a 384-block far plane, over-reporting by 19% and costing a round. **A tool
that lies about the one thing it exists to check is worse than no tool** — and this is the second
time that sentence has had to be written about a different instrument. Now takes the far plane from
whichever projection actually wrote the texture, which with no terrain program really is `zFar`.

**`collectShadowChunks` documented a cost it does not have.** Its comment claimed "a few hundred
validated pointer lookups per frame, because the shadow distance is small" — but the caller
deliberately passes the *render* distance rather than `shadowDistance`, for the reason written at the
call site, so it walks a 769-block cube in 32-block steps: 25³ = **15,625** lookups a frame. It is
affordable and is not the thing to optimise first; the comment is what needed fixing, because "a few
hundred" is the figure someone would budget against when deciding whether to widen the radius. The
same comment now records that only `voxelSize = 1` meshes are collected, so nothing outside the LOD-0
radius casts a shadow at all.

## `far` is 32x Minecraft's, and packs hardcode thresholds against it

**Not a bug, and not something to "fix" by changing `far`.** Recorded because it is a structural
mismatch that will keep producing symptoms, and because the first symptom it plausibly explains is
still open.

Minecraft conflates two numbers that Cubyz separates. There, `far` is the render distance in blocks
*and* the projection's far plane, so a pack can use it for "how far does the world extend" and "what
normalises depth" interchangeably. Here those cannot be the same: Cubyz draws LOD chunks out to
`renderDistance*chunkSize << highestLod` — 12288 blocks against a 384-block full-detail radius — and
`far` has to be the LOD-extended figure or every LOD chunk clips, while `depthLinear` only agrees
with the depth actually written when the `far` uniform matches the far plane. Both constraints are
real and the section above derives them. **Nothing here should change.**

The consequence is that every `x/far` in a pack, and every threshold expressed in `far`-normalised
units, is off by the ratio between Cubyz's LOD horizon and Minecraft's render distance — 32x at the
defaults, 48x against a typical 16-chunk Minecraft. Complementary makes this explicit: `lib/common.glsl`
is literally `float renderDistance = far;` unless Distant Horizons or Voxy is present.

Two measured examples, both computed from the pack's own source rather than observed:

- **Its TAA edge detector cannot fire on ordinary geometry.** `lib/antialiasing/taa.glsl` marks an
  edge when `max(|Δz0|, |Δz1|) > 0.09` in `GetLinearDepth` units. At Minecraft's `far` of 256, a
  pixel five blocks away registers an edge against a neighbour past about 12 blocks, and one at ten
  blocks against a neighbour past 23 — ordinary silhouettes. At `far = 12288`, the pixel at ten
  blocks needs a neighbour past **590 blocks**. Sky and far terrain still trip it; nothing local
  does.
- **Its border fog is `(lPos/renderDistance)^16`.** At 384 blocks that is about 8e-25. The pack's own
  distance fog is effectively switched off.

**Why the first one matters for the open temporal-history item.** `edge` is the only term carrying
camera translation into the blend weight:

    blendFactor *= max(exp(-velocityFactor)*blendVariable + blendConstant
                       - min(length(cameraPosition - previousCameraPosition), 0.05)*edge,
                       blendMinimum);

With `edge` pinned near zero that subtraction vanishes, and at the live default (`TAA_SMOOTHING 3`,
which the options file leaves alone) the history weight while walking stays at 0.7 where the pack
intends 0.4 at depth discontinuities and 0.35 on leaves — with `prvCoord` landing off-grid every
frame, so the history is resampled continuously and only `ClipAABB` fights the blur. That is a
mechanism for "the image softens over ~60 frames of movement and recovers when standing still", and
it sits **downstream of everything already eliminated**: the camera delta, `framemod8`, `velocity`
and `eyeBrightness` are all inputs to a blend whose edge term is dead before they are consulted.

This is a hypothesis derived by reading and arithmetic, **not a measurement of the running game**,
and this file's own history says that is exactly the kind of claim that has been confidently wrong
here before. The cheap way to settle it is to log `edge` — or the resolved `blendFactor` — from
`composite6` across a walk, which is a smaller instrument than the history-buffer readback the
handoff proposes and answers a question that readback would not.

If it does hold, the fix is *not* to retune `far`. Iris's own answer to "the world extends further
than the vanilla render distance" is the Distant Horizons uniform set — `dhRenderDistance`,
`dhFarPlane`, `dhDepthTex` — which Complementary already branches on, three lines above the alias
quoted here. Supplying that set is the structurally honest route and is a feature, not a fix.

## The rain that was never falling

The longest-running symptom in this project's history, and the smallest fix: **the whole scene turned
flat grey the instant the player started walking, and recovered the moment they stopped.** It survived
every bisect thrown at it — TAA off, clouds off, light shafts off, motion blur off by default — and it
was present in every configuration, which is what eventually made it findable.

The cause is one line of `expression.zig`:

```zig
smoothStates: std.AutoHashMapUnmanaged(u32, SmoothState) = .empty,   // keyed by node index
```

`parse` builds a **fresh node list per declaration**, so indices restart at 0 for every one of them,
and a single `Evaluator` is shared across a pack's whole declaration set (`customuniforms.Set`). Two
`smooth()` calls landing at the same index *in their own trees* therefore shared one accumulator. The
file's own doc comment states the contract it was violating — *"Identity is the call site... Iris
hands each resolution a fresh accumulator"* — and Iris does exactly that, a new `SmoothFloat` per
resolution in `IrisFunctions.java`.

Complementary collides squarely:

```
variable.float.moved     = smooth(2, moving, 0, 31536000)
uniform.float.rainFactor = smooth(1, rainStrength, 3, 3)
```

`moving` is `if(difSum > 0.0 && difSum < 1.0, 1, 0)` over the camera delta — a pure binary "did the
player translate this frame". And `moved`'s fadeUp is **0**, which `SmoothState.update` treats as a
*snap*, not a fade. So the first walking frame pins the shared slot to exactly 1.0, and `rainFactor`
— which must be a hard 0, because `rainStrength` is a documented constant 0 in `unsupported` — reads
**0.96** for as long as the player keeps moving.

That is not a subtle knob. `lightAndAmbientColors.glsl` replaces the sun and ambient colours wholesale
via `mix(clearLightColor, rainLightColor, rainFactor)`, and `colorMultipliers.glsl` replaces the light
multiplier with its own channel **average** — literal desaturation to grey. Warm tan sand to flat
grey, cool cast, ground darkened, sky washed.

The shape matched too, and nothing else did. The transition is asymmetric **by construction**:
instantaneous on the first walking frame because `fade == 0` is a snap, and exponential over ~0.3 s
when the player stops because `rainFactor`'s own half-life takes over. That is a one-frame step into a
75-frame plateau with a gradual settle afterwards, which is precisely what the recording measured.

Two notes worth keeping:

- **`frameTimeSmooth` shares the same slot**, so while walking it read ~0.94 instead of ~0.016, making
  Complementary compute `frameCounter % int(0.06666 / frameTimeSmooth + 0.5)` — an integer **modulo by
  zero** — in its light-shaft path. Compiled out at the current settings, but it means every earlier
  light-shaft bisect was comparing against undefined behaviour on exactly the frames being tested.
- It was found by a **multi-agent fan-out** over six independent lenses after several solo rounds had
  failed, and it was trustworthy because the hypothesis cited exact `file:line` for every claim.
  Verifying those citations by hand took minutes. The verification phase of that run died to a usage
  limit, so its own "survivors" count was meaningless — the value was in the citations, not the vote.

## Water, in four separate bugs

Water was wrong in four independent ways at once, which is why it resisted a single explanation.

**It had no wave detail, because `texture.<stage>.<sampler>` was unimplemented.** Complementary
builds its water normals by sampling `gaux4` four times per fragment — `normalMed`, `normalSmall` and
two octaves of `normalBig`. `shaders.properties` says what `gaux4` is:

    texture.gbuffers.gaux4=lib/textures/cloud-water.png

With the directive unimplemented, `gaux4` fell through to colortex7 — an unrelated render target — and
the wave normals came out of garbage. Flat mirror water. This file had previously dismissed the
directive as *"mostly points at Minecraft assets Cubyz does not have"*, which is true of Nostalgia's
and Sildur's bindings and **not** of Complementary's, which points at a file inside the pack.

The implementation covers the 2D-image form and is explicit about the rest: `minecraft:` asset paths
and raw 3D `.dat` volumes (Kappa, photon) are counted and logged rather than silently skipped, because
a partially implemented directive reads exactly like a finished one.

**It had no colour, because `glColor` was white.** Complementary reads it twice — as the water's own
colour and as `translucentMult = normalize(sqrt2(glColor.rgb))`, the tint applied to everything seen
*through* the surface. At white the second collapses to a neutral grey, so the water stopped colouring
the riverbed at all and read as clear glass.

Minecraft carries the water tint in the vertex colour; **Cubyz keeps the same quantity somewhere
else** — `transparent_fragment.frag:156` reads a per-texel `absorption` from the reflectivity array
and multiplies the blend by it. The prologue now supplies that as `glColor`, for the translucent pass
only: opaque blocks default to `Image.whiteEmptyImage` for absorption, so the sample would be a white
no-op on the renderer's hottest vertex path, and the only blocks shipping an `_absorption.png` are
water and the stained glasses — exactly the translucent set.

**The tint was too weak, because the two are different quantities.** Cubyz's absorption is
`(0.565, 0.816, 0.941)` — a transmission coefficient applied **once per block traversed**, so the blue
accumulates with depth and one block's worth is nearly clear. Minecraft's `glColor` is the colour
water already *is*, with depth handled separately by the pack. Cubed — roughly three blocks of
traversal — that is `(0.18, 0.54, 0.83)` against a Minecraft biome water colour of about
`(0.25, 0.46, 0.89)`. The exponent is a unit conversion, not a taste knob, but it is a **judgement**
in a way the other three fixes are not: the two engines genuinely disagree and no exponent matches
exactly.

**Its foam flickered, because Cubyz models fluids as full cubes.** Complementary gates water foam on

```glsl
foam *= clamp((fract(worldPos.y) - 0.7) * 10.0, 0.0, 1.0);
```

Minecraft renders fluids at 14/16, so a surface sits at `y = N + 0.875` — a stable value well clear of
the threshold. Cubyz's water is `.model = "cubyz:cube"`, so its surface sits at an **integer**, and
`fract` of a value on a floating-point boundary rounds to either 0.99998 or 0.00002 depending on the
pixel and the frame. The foam appeared and vanished wholesale.

The fix lowers fluid top rims by an eighth in the pack prologue, gated on Cubyz's own `.tags =
{.fluid}` carried to the GPU as a bit in the existing `blockids` table. Cubyz's own rendering is
untouched — this is the pack prologue, which only runs with a shaderpack loaded.

**The first attempt lowered only half the surface**, and the reason is an engine fact worth knowing
before touching geometry. `chunk_meshing.zig:918` emits every transparent boundary **twice**:

```zig
if (block.hasBackFace()) {
    appendNeighborFacingQuads(block, neighbor.reverse(), pos, true, ...);   // back
}
appendNeighborFacingQuads(block, neighbor, neighborPos, false, ...);        // front
```

Those calls pass **different positions**, so one physical plane arrives as two coincident quads: one
with corners at local `z≈1`, expressed in the water block, and one at `z≈0`, expressed in the block on
the other side. Testing only `z > 0.99` moved one of them and left the other, producing two water
layers an eighth apart — lowered when seen from underwater, unmoved from above. The user diagnosed it
from the image faster than any amount of source reading would have: *"there might be two layers of
water"*. The quad normal is what separates a fluid *top* from a fluid *bottom*, both of which sit at
`z≈0` in their respective frames.

## What the reconstruction broke, and what that taught

`C:\Cubeland` was deleted with no git repository, no backup and nothing in the Recycle Bin. This
tree was rebuilt from Claude Code conversation transcripts — see `RECOVERY.md` at the repository
root for the method and the per-file accounting. 98.6% of the source came back; the rest had to be
rewritten, and the bugs that produced are worth recording because **they are not the usual kind**.

An ordinary bug is a wrong line. These were *absences*: a function that no longer existed, a
struct field that was never declared, an argument that stopped being passed. They share a shape —
**the code still compiled, and the failure appeared somewhere far away and much later.**

### The viewport stopped following the buffer

Symptom: the sky rendered as a flat grey wash with a **hard vertical seam** near the middle of the
screen.

`targets.viewportFor` was gone. It survived only as a *reference inside another function's
comment* — `bindForPass` still explained at length that "`viewportFor` already assumes the render
area is the extent of the buffers the pass writes. This is what makes that assumption true."
Nothing implemented that assumption any more, so every pass got a full-screen viewport.

Nostalgia declares `size.buffer.colortex4 = 256 256` and renders its sky capture into it through a
directional projection. Allocated correctly at 256x256, rasterised at 1280x720: the sky occupied a
fraction of its own texture, the rest held stale content, and `projectSky(direction)` reconstructed
a sky from mostly-unwritten texels. The seam is where the written region ends.

**The lesson is about documentation, not about viewports.** A comment describing a collaborator
outlived the collaborator. Prose that asserts another function's behaviour is a claim nothing
checks — and here it read as evidence that the mechanism was present.

### Every shadow lookup compared against the albedo

Symptom: a 10.8 MB log — 35,830 copies of one driver warning about a shadow sampler reading a
non-depth texture.

`bindSamplerUniforms` had lost its tail. It assigned `colortex*`, `depthtex*` and the legacy
aliases, then simply stopped: `shadowtex0`, `shadowtex1` and the `shadowcolor` pair were never
assigned a unit. An unassigned sampler uniform reads **unit 0**, which during the post chain holds
colortex0 — so every shadow comparison in every pass was testing the pack's depth against the
scene's own colour buffer.

This is the founding bug of this file ("An unassigned sampler uniform reads texture unit 0")
arriving a second time, in a function whose *earlier* half was intact. Two related absences came
with it: `runPass` never bound the per-program comparison sampler objects, and
`resolveShadowComparison` was being called for only one of the three pass builders.

**The driver was the one that noticed.** No test could — the units are assigned at runtime against
a linked program. A dirty GL log remains the strongest signal this project has.

### Three hooks the renderer no longer called

Symptom: terrain lit by the pack under a **pure black sky**, and no shadows anywhere.

`runPreparePasses`, `renderShadowMap` and `restoreSceneDepth` were all still exported by
`bridge.zig`, still fully implemented, and **called from nowhere**. `renderWorld`'s hook calls are
one line each, and the four the reconstruction could not anchor were exactly these. `runPreparePasses`
was additionally missing from `build.zig`'s `renderHooks`, so even the forwarder had no entry.

Nostalgia draws its sky *in the prepare chain*, so with those passes never running the albedo's sky
region stayed at its clear colour. The shadow map was never rendered into at all.

**A hook is invisible when absent.** A missing call site produces no error, no warning and no
unused-symbol complaint — the implementation sits there looking healthy. Anything that reaches the
engine through a one-line call needs its call sites enumerated somewhere, which is what
`build.zig`'s `renderHooks` list now is.

### The vestigial stopgap that outlived its replacement

Symptom: **every** program failed with `C7101: Macro ResolutionScale redefined`.

`pipeline.standardMacros` still appended `#define ResolutionScale 1.0` to every program's define
list — the hack from before `lib/options.zig` existed. Once the options system rewrites the
option's own declaring line, as Iris does, the injection collides with the very line it used to
stand in for. One error, and no program in the pack survives it.

This one is not a reconstruction artifact so much as a reconstruction *exposure*: the stopgap and
its replacement had coexisted harmlessly only because no real pack had been extracted since. The
general form is worth keeping — **when a mechanism is replaced, the replacement's first real test
is also the moment the old one becomes actively wrong.**

### And one that was not in the code at all

The loader extracts packs into `shaderpacks/.cache/<name>/` and prefers an extracted folder over a
zip. The reconstruction had written the handful of pack files earlier sessions happened to read
into exactly those paths — one file for Kappa, against 408 in the real archive. The loader found a
`shaders/` root, discovered no programs, and reported `contains no usable programs` while the
complete 3.8 MB zip sat unread beside it.

**Writing into a cache is worse than writing nothing**, because a cache is trusted by construction
and its whole purpose is to be preferred over the real source. Every file there was individually
valid; the directory was radically incomplete; and nothing re-validates a cache.

### The sweep for the rest of them, and what it found

The three absences above were each found by a symptom. That does not scale — an absence with no
symptom on the current fixture is invisible until a pack exercises it — so the remaining ones were
looked for **mechanically**: every symbol declared in the mod, counted against every reference to it
across `mods/` and `src/`, with comments stripped so a name that survives only in prose does not
count as a use. Two questions, and only the second found anything:

- *referenced but defined nowhere* — cannot exist, since the tree compiles. Except in comments,
  which is the `viewportFor` shape.
- *defined but referenced nowhere* — the `runPreparePasses` shape. **This is the productive one.**

It flagged thirteen symbols, of which four were real and the rest are dormant instruments.

**`uniforms.uploadFullscreenMatrices` had no call site, so no post-chain pass got compat matrices
at all.** The worst of the four. `pipeline.runPass` uploaded the Iris uniform set and the samplers
and stopped; the `cubyz_*` fixed-function matrices were uploaded only by the four *geometry* paths
in `bridge.zig`. A composite program is a separate program object, so its
`cubyz_ModelViewProjectionMatrix` had never been written at all — GL's zero. The function's own doc
comment describes the resulting image precisely, having been written when it was measured: a hard
vertical edge at exactly `width/2`, Cubyz's own output showing around a small quad that swings with
the view.

It is invisible on the fixture **by construction**. Nostalgia and Kappa write
`gl_Position = vec4(gl_Vertex.xy*2.0 - 1.0, 0.0, 1.0)` by hand and never read a matrix;
Complementary writes `gl_Position = ftransform()` in every post-chain vertex stage —
`composite.glsl` through `composite7.glsl`, `deferred1.glsl` and `final.glsl`, e.g.
`composite1.glsl:365` inside `#ifdef VERTEX_SHADER`. So the pack that needs it is the one that was
not loaded. The same call also supplies `gl_Fog`, which the post chain had likewise been running
without.

**`packtextures.Set.bindOverrides` had no call site**, so `texture.<stage>.<sampler>` was loaded and
never bound. That is the directive whose absence this file already records under "Water, in four
separate bugs": Complementary declares `texture.gbuffers.gaux4=lib/textures/cloud-water.png` and
samples it four times per water fragment to build its wave normals, and unbound `gaux4` falls
through to colortex7. The loading half survived the reconstruction — `loadCustomTextures` runs and
counts what it skipped — and the four lines that apply it did not. Its own doc comment says where
they go: *"Call after `targets.bindSamplers`, which binds the buffers this deliberately replaces."*
Now called from all four binding sites, scoped by stage: `.gbuffers` for terrain, sky and water,
`.shadow` for the shadow pass, and `Stage.forProgramKind` for the post chain.

**Two lists that exist to keep a gap visible were read by nothing.** `uniforms.unsupported` and
`pack.unsupportedDirectives` both carry doc comments arguing that a value parsed and then quietly
ignored is worse than one that is missing — and neither was logged anywhere, so both had become the
thing they warn about. The coverage report cannot cover this by construction: those uniforms *are*
supplied, as documented constants. They are reported now, filtered to what the pack actually asks
for — the constants it declares, and the directives whose value differs from the default — because
printing all of them every load is noise nobody reads.

**`prologue.AttributeTypes.differFromDefault` had no caller**, so the load never logged the resolved
attribute widths. Its own comment and the photon section above both say that line exists precisely
so the fix can be told apart from a no-op, since a width fix is invisible in the image: the program
either compiles or it does not.

**Still open, and deliberately not fixed here.** `prologue.bindingsMatchEngine` names the four SSBO
binding points with a doc comment saying they are named *"rather than left as bare numbers in the
generated GLSL"*. They are bare numbers — `binding = 3`, `4`, `10`, `6` at `prologue.zig:139`, `148`,
`150` and `165` — and the struct is referenced nowhere. The block-id binding one paragraph below is
written from its constant and says why, so the intent is clear and the substitution is what was
lost. It is not a live bug, since the numbers currently agree with `chunk_meshing.zig`; it is a
landmine, because the next person to change a binding will update the constants and not the
literals. The fix means splitting a multiline literal into `print` calls with every brace doubled,
inside the prologue — which this file records as having taken four programs down once already — so
it is worth doing deliberately rather than in passing.

The rest of what the sweep flagged is dormant instruments, not defects:
`targets.sampleCenterDepth`, `sampleAtFraction` and `captureDepth`, and `pipeline.diagTick`/`mark`,
which is labelled `TEMPORARY` in its own comment. `centerDepthSmooth` itself is live and fed from
`uniforms.centerDepth.sample`; `captureDepthSnapshots` is the depth path that runs. They are
reachable code with no caller, which is what a shelved probe looks like.

**The generalisation worth keeping.** A missing call site produces no error, no warning and no
unused-symbol complaint, and the implementation sitting there looks healthy — this file already says
so about hooks. What the sweep adds is that you do not need a symptom to find one, and you should not
wait for a symptom, because *which* absence is visible depends entirely on which pack is loaded.
Four of these five were invisible on Nostalgia and three of them break Complementary.

### The shadow map was starved again, and nothing said so

Found by grepping for a *shader* uniform against the Zig that drives it, which the symbol sweep
above does not reach — it counts Zig symbols, and this absence spans the language boundary.

`assets/cubyz/shaders/chunks/fillIndirectBuffer.comp` still declared
`layout(location = 7) uniform bool ignoreVisibility`, with the full doc comment explaining why a
shadow pass needs it. **Nothing in `src/` or `mods/` ever set it.** `commandUniforms` had no field
of that name, and locations are resolved by `glGetUniformLocation(field.name)` over that struct's
fields, so the uniform never got a location and never got a value. GL reads an unset `bool` as
false — so the shadow pass was culled against the camera's own occlusion state again, which is the
exact bug "The light shaft through solid rock" measured at 22.5% shadow coverage against 69.4%.

`ignoreDirection` was worse: **gone from the shader entirely**, surviving only in this file's prose
and the handoff's "Engine changes that must not be reverted" table. `isVisible(i%7, playerDist)` ran
unguarded, so every chunk above the player still lost its up-facing group — the half of that fix
which is chunk-count-invariant, and therefore the half that looks like a hard limit rather than a
bug.

**Measured afterwards, and it did not change the standing-still jitter — record that as an
elimination.** It was fixed on the strength of a mechanism (the camera's occlusion state oscillates
at a visibility boundary with no input, and each flip adds or removes an occluder from the shadow
map), which is the kind of reasoning this file repeatedly records as producing confident wrong
answers. The fix is kept because it is wrong on its own terms and worth 22% -> 69% coverage, but it
is not the jitter.

Both are restored: the shader declares `ignoreDirection` at location 8 and guards the direction
test with it, `commandUniforms` carries both fields, `drawChunksForShadow` sets both to 1, and
`drawChunksOfLod` sets both to **0 explicitly**. That last part is not tidiness. The shadow pass
runs earlier in the frame and sets them to 1; leaving the camera path to inherit that would disable
occlusion culling for the entire world, which costs frame rate rather than correctness and so
presents as "the game got slower" with nothing in any log.

**Why this is worth its own section.** Every absence found so far has been Zig calling Zig, and the
sweep that finds those cannot see this one: the declaration is in GLSL, the caller is in Zig, and
the join between them is a *string* resolved at runtime. Nothing errors when it breaks. There is no
unused-symbol warning on either side, `glGetUniformLocation` returning -1 is a normal condition that
the uniform-setting path ignores by design, and the shader compiles perfectly with a uniform nobody
writes. **A uniform is a call site too, and it is the least visible kind there is.**

The generalisable check, and it is cheap: for every `uniform` a Cubyz shader declares, there should
be a field of the same name in the matching uniform struct. That is a grep, and it should be run
against the other shaders in `assets/cubyz/shaders/` before trusting any of them.

### Nothing accumulated across frames, again — this time through a lost fallback

The jitter, and the one the reconstruction hid best. `swapFlippedBuffers` was present, called, and
correct in every respect except the two numbers it copies:

```zig
c.glCopyTexSubImage2D(c.GL_TEXTURE_2D, 0, 0, 0, 0, 0, target.width, target.height);
```

**`Target.width` is 0 for a screen-sized buffer.** That is its documented meaning — the field's own
doc comment says "the buffer's own size, or **0 meaning 'follows the screen'**" — and every other
reader in `targets.zig` falls back to `self.width`: the allocation does, `viewportFor` guards on it,
`blitToScreen` does, both sampler paths do. This one did not. So for every screen-sized target the
copy was a **zero-by-zero region**, which GL accepts without complaint and which copies nothing.

The consequence is the section "Nothing accumulated across frames" above, reinstated in full and
narrowed to exactly the buffers that matter: a target with a declared `size.buffer` copied correctly,
and every screen-sized one did not. Nostalgia's history buffers are all screen-sized —
`colortex6`/`colortex9` for TAA, `colortex12`/`colortex13` for the SSPT accumulation — while
`colortex10`/`colortex11`, the reflection capture, are declared `1024 512` and so kept working. **The
subsystem that appeared healthy and the one that did not were separated by nothing but whether the
pack had written a size for them.**

The symptom, in the user's words, is what named it: *"jitters in the distance but not super close by,
and also some weird fuzzy artifacts in the distance too like tiny fuzzy orbs are building the
distance"* — with the pack off, neither happens.

Both halves fall out of a dead history and neither falls out of anything else:

- **Distance-weighted shimmer is unresolved TAA jitter.** The pack offsets the projection by a
  sub-pixel `taaOffset` every frame and relies on accumulation to average it away. A near surface
  spans many pixels, so a sub-pixel shift barely changes it; distant terrain is high-frequency detail
  at around a pixel per feature, where the same shift changes which sample is taken outright. So the
  identical error is invisible up close and obvious at the horizon.
- **"Fuzzy orbs" are path-traced samples that never converge.** At `profile = Ultra` Nostalgia runs
  `ssptEnabled` with an SVGF denoiser, whose accumulation buffers are exactly `colortex12`/`13` via
  `program/deferred/accumulate.fsh` (`const bool colortex12Clear = false;`). A temporal denoiser with
  no history shows its raw sparse samples, which is a field of soft blobs, densest where the ray
  budget is thinnest.

**Two method notes, both of which this file has recorded before and neither of which stopped it.**

The first is that **"I checked that path and it is structurally sound" is not a measurement.** Earlier
in this same session the accumulation path was walked and cleared: `flip.finalState` counts parity
over post-chain passes only, `final` contributes nothing, the gbuffers stage is correctly outside the
flip sequence, `swapFlippedBuffers` is called at the end of `runPostChain`, and Nostalgia's
`colortex6Clear`/`colortex9Clear = false` are parsed and honoured. Every one of those statements is
true, and the copy still moved zero pixels. The reasoning stopped one level above the arguments.

The second is that **the user's description contained the answer and the questions did not.** Two
rounds were spent on "when does it happen" — turning, walking, standing still — which is the question
the README says to ask, and it was the right question for a different bug. What actually located this
was *"in the distance but not super close by"* plus *"tiny fuzzy orbs"*: one clause names a spatial
frequency dependence and the other names a specific subsystem. Neither was asked for. This file's own
rule — "their incidental remarks carry the best clues and are not offered as hypotheses" — has now
been demonstrated three times, and the corollary is worth stating: **ask what it looks like before
asking when it happens.** Shape is cheap to describe, it costs the user nothing to answer, and it
survives being wrong about the mechanism.

**The class, and how to find the next one.** This is a *lost fallback*: not a missing function and
not a missing call site, but a live call whose argument stopped being computed. It is invisible to
the symbol sweep, because every symbol involved is defined and referenced; invisible to the type
checker, because `0` is a perfectly good `u31`; and invisible to GL, because a zero-sized copy is
legal. The generalisable check is the one the field's doc comment states outright: **a sentinel value
is a contract, and every reader has to honour it.** `Target.width`'s sentinel had six readers and
five of them did. Grepping a sentinel field for readers that do not test it is a two-minute pass and
it should be run on `Target.width`'s siblings.

## What Nostalgic Red Voxels found, and the four features it needed

The seventh pack, and the first the user tried after the reconstruction. It loaded - 31 programs,
12 passes - with two programs failing, and both failures turned out to be feature gaps rather than
bugs: things Iris does that this bridge had never been asked to do. Everything below was found by
reading the log and the pack; no launch was spent on a hypothesis.

### `texelFetch` had no flavour

    gbuffers_terrain (frag) failed to compile:
    0(6630) : error C1115: unable to find compatible overloaded function "texelFetch(sampler2DArray, ivec2, int)"

The pack averages a 16x16 block of texels around the tile centre to stop lava's brightness
pulsing, and it does that with `texelFetch(tex, itexCoordC + ivec2(x, y), 0)`. `texelFetch` was not
one of the sampling functions the per-call-site redirect knows, so the call was left alone, `tex`
became the `sampler2DArray`, and no such overload exists. This is the `textureLod`-versus-`texture`
lesson one flavour further: integer texel coordinates are not a fourth spelling of the same lookup,
the helper has to add the array layer *as an integer* and must not scale anything. `Flavour.fetch`,
`cubyz_fetchArray`, and the `cubyz_fetchAny` dispatch overloads for the macro case.

### The shadow program has a geometry stage, and the bridge never ran one

    shadow failed to link:
    error: "absMidCoordPos" not declared as input from previous stage

Grepping the pack for the varying shows the shape at once: the vertex stage writes `absMidCoordPosV`,
the fragment reads `absMidCoordPos`, and `program/shadow.glsl`'s `GEOMETRY_SHADER` section is what
renames one to the other - along with `texCoordV`, `lmCoordV`, `matV`, every varying the program
has. Iris attaches a `.gsh` beside a program whenever the pack ships one. This bridge read `.vsh`
and `.fsh` and nothing else, so the two stages it did compile could never link, and no option in the
pack could change that.

Geometry stages are loaded now (`Program.geometrySource`, `world0/shadow.gsh` and the root fallback,
like the other two), transformed as `.geometry`, compiled and attached. One thing crosses the stage
from the bridge's side: the vertex prologue's `flat out int cubyz_textureLayer`, which the pack's
geometry code has never heard of and so would never pass through. When a geometry stage exists the
vertex emits it as `cubyz_textureLayerV`, and a generated passthrough declares
`flat in int cubyz_textureLayerV[3]`, `flat out int cubyz_textureLayer`, and sets the output once
before the pack's own `main` runs. It is `flat` and per face, so every input vertex agrees and `[0]`
is the whole story. Tested at the property level: the vertex and passthrough names must pair, and
without a geometry stage the vertex keeps the fragment-facing name byte for byte.

### And that geometry stage is the pack's voxeliser

Which is the part worth being blunt about. NRV3's shadow geometry shader does not exist to render
a shadow map. It declares `iimage3D voxelCols` and `occupancyVolume` unconditionally, includes
`lib/vx/SSBOs.glsl` with `WRITE_TO_SSBOS`, and voxelises the scene into them on every draw - that is
the whole "red voxels" feature, and it needs three things Iris has and this bridge does not: custom
images (`image.<name>` in `shaders.properties`), buffer objects (`bufferObject.N`), and the compute
programs (`shadowcomp*.csh`) that consume what it wrote.

Linking that program and running it would not be "shadows with no colored lighting". An image
unit with nothing bound makes every `imageAtomic*` undefined, and its storage block sits at
`binding=0` - a write into whatever memory is or is not there. So `pipeline.unsupportedResources`
asks the linked program, after preprocessing, for active image uniforms and non-`_cubyz` storage
blocks, and refuses a program that has any, with one line naming them:

    shadow uses resources this bridge cannot supply, so the program is disabled: voxelCols, occupancyVolume, buffer stuff (Iris custom images and buffer objects are not implemented)

That is the same stance this file takes on `COLORED_LIGHTING`: advertising a feature and binding
nothing behind it is worse than declining it. The user-visible result for this pack is terrain
through its own `gbuffers_terrain` and no shadow map, and the log says why in one line rather than
in a link error about a varying.

### `colorimgN` is a different thing, and it is supplied

The pack's `prepare` passes looked like the same problem - `layout(r32ui) uniform uimage2D
colorimg9`, `imageAtomicMin`, `imageStore(colorimg8, ...)` - and are not. `colorimgN` is Iris's
second way of exposing the colortex buffers this bridge already owns, for `imageLoad`/`imageStore`
and the atomics, and the first version of the gate above would have refused every one of them.
`targets.bindImages` binds each `colorimgN`/`shadowcolorimgN` a program declares onto its own image
unit, from `GL_MAX_IMAGE_UNITS` rather than a fixed slot per buffer, and a memory barrier follows
every pass that bound one, plus one at the top of the post chain for the geometry stage and one
after the shadow draw.

**Which side to bind is a judgement, and it is worth stating as one.** The image is the buffer's
*read* side, the same texture the pass's `colortexN` sampler sees. The argument: an image write
does not advance the flip, only a draw buffer does, so a value stored through `colorimg9` in one
pass has to be found by `imageLoad(colorimg9)` and `texture(colortex9)` in the next, and that only
holds if all three name one texture. `Iris/` is gone from this tree, so this was reasoned rather
than read; if a pack's image-written buffer reads stale, this is the first thing to check against
`RenderTargets`.

Two things came with it because the images cannot work without them. `R32UI` was not a format the
loader knew, so `const int colortex9Format = R32UI;` parsed to null and allocated **RGBA8** - and an
atomic on an 8-bit normalised texture is not a wrong number, it is undefined. The integer and
signed-normalised families are in `TextureFormat` now, and an unknown format logs instead of falling
back in silence, which is the class of bug this file keeps finding. And `shadowcolorFormat`, which
this file records as "parsed, textures hardcoded to RGBA8 - **fixed**", was hardcoded to RGBA8 in
this tree: the fix was lost with the rest of `targets.zig` and nothing measured it. Allocated from
the pack's declaration now.

### `at_midBlock`, and `IRIS_VERSION`

Both smaller, both evidence-based. Four of the five packs declare `at_midBlock` - Kappa and
Nostalgia hinge wind displacement on it, Complementary and its derivatives voxelise with it - and
none of them had ever received a value: an unfed attribute reads `(0, 0, 0)`, so every vertex
claimed to sit at its block's centre and foliage waved as a rigid body. The prologue supplies it
from the corner offset the position was just built from, `(0.5 - corner) * 64` in Y-up, at the width
the pack declared, through the same `AttributeTypes` mechanism as the other three.

`IRIS_VERSION` is defined at `10800`: the lowest version that clears every threshold the corpus
tests for a uniform this bridge supplies - `>= 10800` is where packs start reading
`cameraPositionFract`. The higher thresholds in the corpus only choose between bug workarounds, and
the older path is the safe direction to fall. Features are advertised separately through
`IRIS_FEATURE_*`, and deliberately none of the custom-image, higher-shadowcolor or chunk-fade
flags are set, because none of those exist here.

### The conformance harness was unrunnable

`test/real_pack.zig` called `loadPrograms` with six arguments after the options work gave it seven,
so the multi-pack transform pass this file describes had not run since. Repaired, and run over the
nine packs now in `shaderpacks/`:

    Bliss_v2.1.2_(Chocapic13_Shaders_edit)    38 programs   76 stages   0 leftovers
    BSL_v10.1.3                               28 programs   56 stages   0 leftovers
    ComplementaryUnbound_r5.8.1               30 programs   60 stages   0 leftovers
    Kappa_v5.3                                51 programs  102 stages   0 leftovers
    Nostalgia_v5.1                            49 programs   98 stages   0 leftovers
    NostalgicRedVoxelsV3                      31 programs   63 stages   0 leftovers
    photon_v1.3b                              54 programs  108 stages   0 leftovers
    rethinking-voxels_r0.1-beta9              31 programs   63 stages   0 leftovers
    Solas Shader V3.7b                        23 programs   46 stages   0 leftovers

The odd stage counts are the geometry stages, loading. This is the transform only - what the driver
makes of the result needs a launch per pack, and five of the nine have never been launched.

The invocation, since `run.bat` never had it and the root has to sit at the mod level:

    zig test --dep main --dep pack --dep install -Mroot=<a file at mods/irisbridge/ importing test/real_pack.zig>
             --dep main -Mpack=mods/irisbridge/lib/pack.zig --dep main -Minstall=mods/irisbridge/lib/install.zig
             --dep vec -Mmain=mods/irisbridge/test/main_stub.zig -Mvec=src/vec.zig

### The ceiling, stated plainly

"Any Iris pack" is not a reachable target and this file has said so since its first paragraph. What
is reachable is the honest one: every pack loads, every program either runs correctly or is refused
with a reason, and the refused set shrinks as features land. After this session the largest
remaining reason is one feature with three parts - custom images, buffer objects, and compute
programs - which is what Complementary's colored lighting, both voxel packs, and photon's light
propagation all stand on. It is bounded, well specified by the packs themselves, and it cannot be
verified without the driver; that makes it the next thing, and not a thing to do blind.

## Nine packs on the driver, and the regression the first look hid

The user launched all nine packs - ten runs, entering and leaving because some of them made the
menus unreachable - and put the Iris 1.7.3 source at the repository root. Every run had hundreds to
thousands of `[error]` lines, Nostalgia included, which had been at zero. That is the regression to
chase first, and it was one thing wearing several faces.

### One `texelFetch`, one root cause, four packs

    Nostalgia    shadow (frag), gbuffers_water (frag):  error C1102: incompatible type for parameter #1 ("s.29")
    Complementary, Kappa                                 the same, in the same two programs

The dumped source names it: `cubyz_fetchArray(tex, location & 255, 0)` inside Nostalgia's noise
fetch, whose parameter is `sampler2D tex`. The per-call-site redirect keys on the *spelling* of the
first argument, `tex` is one of the block-texture names, and `texelFetch` had just been taught to the
redirect - so a pack function that merely names a parameter `tex` had its fetch sent to a helper that
only accepts the array. The terrain program compiled because it never includes that function.

The fix is not to make the redirect smarter about scopes. The type of a sampler is only truly known
to the compiler, and overload resolution is the one place that knowledge exists, so every array
helper - `cubyz_sampleArray`, `Lod`, `Grad`, `cubyz_fetchArray` - now has a plain `sampler2D`
passthrough beside it. A pack local that happens to share a name resolves to the passthrough; the
real block texture, `#define`d onto the `sampler2DArray`, resolves to the array lookup. This is the
same move `cubyz_sampleAny` already made for the macro case, applied one step earlier.

### And that is where the thousand errors came from

    898 to 11211 per run:  OpenGL API error: GL_INVALID_OPERATION error generated. State(s) are invalid: blend.

Not a blend bug. When a pack's `gbuffers_water` is unavailable - failed to compile above, or refused by
the resource gate below - `beginTranslucent` returned false and Cubyz's own transparent shader drew
the water. That shader uses **dual-source blending**, which GL permits against exactly one draw
buffer, and the pack's G-buffer was still bound with every attachment `gbuffers_terrain` named. One
`GL_INVALID_OPERATION` per translucent draw call, and the debug callback logging each of them is what
made the frame crawl and the menus unreachable.

The fallback path is legal now: with no water program, `beginTranslucent` narrows the draw buffers
to the albedo, as `beginCubyzShadedDraws` does for the engine's other draws, and returns true so
`endTranslucent` restores the full list. That path was always reachable - every pack whose water
program ever failed took it - and had simply never been looked at, because on the fixture the water
program never failed.

### Four pack-specific gaps, each read off its own log line

**Solas** - `declaration of "cubyz_blockTextures" conflicts with previous declaration`. It writes
`uniform sampler2D gtexture, noisetex;`, a declarator *list*, and `matchDeclaration` only knew the
single form. The declaration survived the stripper, `gtexture` was renamed onto the prologue's array,
and the two collided. Lists are matched now, and a stripped name is cut out with one adjacent comma
so `noisetex` keeps its declaration; a list whose every name is stripped goes whole. Tested at each
position a stripped name can hold.

**BSL and Bliss** - fourteen programs down to `texelFetch2D requires "#extension GL_EXT_gpu_shader4"`
and `texture2DGradARB requires "#extension GL_ARB_shader_texture_lod"`. Extension-era spellings
that a core profile refuses outright. Iris's `CommonTransformer` renames the set - `texture2DGrad`,
`texture2DGradARB`, `texture3DGrad`, `texelFetch2D`, `texelFetch3D`, `textureSize2D` - and so does
this now, through the same shim mechanism as `texture2D`, with the two-dimensional forms also
joining the block-texture redirect. Plus `uniform.float.sandStorm = 0.0;` - a trailing semicolon the
expression language has no use for and Iris tolerates; trimmed before parsing.

**Nostalgic Red Voxels and Rethinking Voxels** - five programs refused each, `final` among them, and
the screen never received a frame. These packs say what they are in one line of `shaders.properties`:

    iris.features.required=CUSTOM_IMAGES SSBO COMPUTE_SHADERS

Iris reads exactly that line and refuses the whole pack when it cannot provide a required feature
(`ShaderPack.java:196`), rather than loading it into a broken state. The bridge does the same now.
`pipeline.supportedFeatures` names the two Iris feature flags that genuinely exist here - separate
hardware samplers and per-buffer blending - a pack requiring anything else is declined at load with
the list, Cubyz's own rendering stays, and the picker moves on. Optional flags the bridge supports
become `IRIS_FEATURE_*` defines, added after the properties file is read, which is the order Iris
uses (`ShaderPack.java:218`). The per-program resource gate stays as the backstop for a pack that
uses an image without declaring the flag - Solas' shadow, under one option.

And a chain with no `final` now blits colortex0 to the screen itself, which is what Iris does; a pack
that ships none, or whose `final` was refused, no longer shows the GUI over a stale window.

### Two judgements, now checked against Iris

Both were reasoned last session with the Iris tree absent, and both hold.

- **`colorimgN` binds the flipped side.** `IrisImages.java`: *"image bindings are impacted by
  buffer flips"* - `flipped.contains(index) ? alt : main`, the same set the samplers read from. That
  is the read side, as implemented.
- **`IRIS_VERSION` is not an Iris 1.7.3 macro at all.** `StandardMacros.java` defines `IS_IRIS`,
  `IRIS_TAG_SUPPORT`, `IRIS_HAS_CONNECTED_TEXTURES` and the `MC_*` set; the version macro arrived
  later. Under 1.7.3 every `#if IRIS_VERSION >= 10800` in the corpus takes its `#else`. The bridge
  keeps `10800` because it supplies what that threshold gates, and now knows it is claiming a little
  more than the reference it has.

`IrisImages.java` also settled the image *format* question in passing: the image is bound with the
render target's own internal format, which is what `bindImages` does.

### What is verified, and what is not

`zig build test`: 193 mod tests, 73 engine. The conformance harness over all nine packs: every
program transforms, zero leftovers. Nothing in this section has been seen on the driver since the
fixes; the runs that motivated it are the ten from the morning. The next log answers, per pack,
whether the water programs compile, whether Solas' terrain does, how many of BSL's and Bliss's
fourteen remain, and whether the two voxel packs decline cleanly at load.

## The second round on nine packs: a version policy, a lost alias, and the biome

One run this time, every pack cycled through the picker. Against the morning's ten runs the log
moved the right way - compile failures 20 to 4, refused programs 11 to 2, GL diagnostics 11,211 to
396, both voxel packs declining cleanly at load - and what remained had three shapes, each read
straight off its own line.

### Bliss: four post-chain programs, and the number in the `#version` line

    deferred (frag) failed to compile:
    0(2369) : error C1101: ambiguous overloaded function reference "clamp(float, float, int)"
        (0) : gp5 float64_t clamp(float64_t, float64_t, float64_t)
        (0) : float clamp(float, float, float)

The dumped line is `int(clamp(maxIT_clouds / sqrt(exp2(viewPos.y)), 0.0, maxIT))` with `maxIT` an
integer - a Chocapic idiom, legal GLSL, and by the overload rules unambiguous. NVIDIA's compiler
disagrees at `#version 460`, where it exposes `float64_t` overloads of every builtin; and every
pack author who has ever tested against NVIDIA did so under Iris, which does not compile at 460.
`TransformPatcher.java:145` is the rule: **the pack's own version, raised to at least 410 core**.
Bliss is written at `#version 120`, so under Iris it compiles at 410, where the ambiguity does not
arise.

The bridge follows that rule now. `glsl.transform` takes an optional version; the post-chain
builder leaves it unset and gets the pack's own number floored at 410, while the three builders
that splice in the SSBO prologue pass 460, which `gl_BaseInstance` and the storage blocks need.
One consequence had to come with it: the transformer used to drop every `#extension` line on the
grounds that core 460 subsumes them all. At 410, `GL_ARB_shader_image_load_store` and
`GL_ARB_shading_language_packing` are not core, and a pack at `#version 130` enables them for
exactly that reason - so the pack's extension lines are kept, hoisted to just after `#version`
where the specification wants them. The one thing hoisting changes is an `#extension` inside a
conditional block, which now applies unconditionally; nothing in the corpus does that, and a
`: require` on an extension the driver lacks would be the failure mode.

Kappa declares `450 compatibility` and gets `450 core`; Nostalgia and photon declare `400` and get
`410`; the `130` and `120` packs get `410`. This is the first time the bridge's output version has
matched the reference, and it is worth being explicit that it was chosen from the Iris source
rather than from a theory about the driver.

### 396 undefined-behaviour warnings, all Bliss, all one missing table row

    The current GL state uses a sampler (0) that has depth comparisons disabled, with a texture
    object (64) with a non-depth format, by a shader that samples it with a shadow sampler.

Unit 0 is colortex0. Bliss declares `uniform sampler2DShadow shadow;` in every pass that reads the
map - the oldest OptiFine alias - and `bindSamplerUniforms` assigned `shadowtex0`, `shadowtex1`,
`watershadow` and the `shadowcolor` pair, but not `shadow` and not `shadowtex`. So the sampler kept
GL's default unit, a colour texture under a comparison sampler, and the driver said so on every
draw. `resolveShadowComparison`, two functions away, had known both names all along. This is the
founding "unassigned sampler reads unit 0" bug of this file arriving for the third time, in the
same function whose tail the reconstruction had already been found to have lost once.

### The uniforms that were real, and read zero

The coverage report's lists for the new packs were long, and most of each is pack-private voxel
machinery or Distant Horizons. But checking every name against `Iris-1.7.3-1.21.zip` - the tree is
here now, so this is a grep rather than a memory - separated a set Iris genuinely supplies:

| uniform | Iris source | here |
|---|---|---|
| `cloudHeight` | `level.effects().getCloudHeight()`, 192 by default | 192, constant |
| `bedrockLevel`, `heightLimit` | the dimension's bounds | -64 and 256, matching `seaLevel = 64` |
| `lightningBoltPosition` | camera-relative bolt, `.w` set while one exists | zero, constant |
| `currentPlayerHealth`, `maxPlayerHealth` | health as a fraction, and the maximum raw | from `Player.super` |
| `is_sneaking`, `is_on_ground` | `CommonUniforms` | from `Player.crouching`, `Player.onGround` |
| hunger, armour, air, `isSpectator`, `is_hurt`, `is_burning`, `is_invisible`, `is_sprinting` | | constants, in `unsupported` |

`lightningBoltPosition` matters more than a constant zero suggests: photon smooths it into a
flash term, and an *unbound* uniform fails that expression outright where a bound zero evaluates.
`cloudHeight` at zero had BSL and Solas drawing their cloud layer at the player's feet.

### The biome under the player

Four packs failed a whole family of custom uniforms - `isSwamp`, `isSnowy`, `isDesert`,
`isJungle` - with `UnknownVariable`. They are written as

    uniform.float.isSwamp = smooth(4, if(in(biome, BIOME_SWAMP, BIOME_MANGROVE_SWAMP), 1, 0), 10, 10)

against `biome`, which the bridge did not supply, and `BIOME_SWAMP`, which is not a uniform at all:
Iris defines one such constant per registered biome for the expression language
(`IrisDefines.java:28`). With neither, every one of those uniforms was dropped and never uploaded.

Cubyz has biomes, the client already tracks the current one for its own fog
(`game.World.playerBiome`), and their names overlap Minecraft's in the way block names do. So
`lib/biomemap.zig` does for biomes what `blockmap` does for blocks: a table of Minecraft's biomes
with their vanilla climate and Iris's category ordinals, a `BIOME_<NAME>` lookup wired into the
expression environment, and a match from the Cubyz biome *family* - the first path segment of
`cubyz:desert/oasis` - to the vanilla biome it stands in for. `biome`, `biome_category`,
`biome_precipitation`, `temperature` and `rainfall` are then supplied from the matched entry. An
unmatched family keeps plains as its climate, deliberately: the zeros of an unsupplied uniform read
as a frozen biome to every pack, which is how snow effects had been switching on in a desert.

The climate numbers are Minecraft's, so a pack tuned against them sees the world it expects; the
ids are table indices and only have to be self-consistent, because packs compare `biome` against
the constants and never against literals. Tests pin the constants to the ids, the equivalence table
to names the biome table has, and the family match across variants.

### What is verified

`zig build test`: 197 mod tests, 73 engine. The harness over nine packs: every program transforms,
zero leftovers, geometry stages included. Nothing in this section has been seen on the driver; the
next log answers whether Bliss's four programs compile at 410, whether the shadow warnings are
gone, and whether the biome-gated effects now follow the terrain.

## The third round: `in()`, the category constants, the End's flash, and Bliss's clamp

One run again, every pack cycled through the picker (`logs/ts_1788293161612387300.log`, the 15:07
run of 2026-09-01), and the handoff had already read it into four items. Three were mechanical and
are done blind, as it asked. The fourth could not be fixed the way it proposed, and the reason is
the more useful finding.

### `in()` did not exist, and eight arguments was the ceiling

    custom uniform 'isSwamp' failed at runtime: UnknownFunction      BSL, Solas, Complementary's in* family
    custom uniform 'isCold' failed at runtime: BadArity             BSL; Solas's isSnowy; Bliss's noPuddleAreas

Every biome test in the corpus is written as `in(biome, BIOME_SWAMP, BIOME_MANGROVE_SWAMP)`, and
the expression language had no `in`. Iris registers it as a fake vararg - one overload per length
from 2 to 32, all floats, `==` on the float value (`IrisFunctions.java:714-736`) - so ints arrive
through the implicit cast, and `apply` does the same. The second error was arriving before the
first could: `evaluateCall` evaluated arguments into an eight-slot buffer and returned `BadArity`
past it, so BSL's eleven-biome `isCold` and Bliss's eighteen-entry `noPuddleAreas` never reached
the function lookup at all. Both limits are one constant now, `expression.maxArguments = 32`,
Iris's own ceiling.

The part worth writing down is the buffer that did not fail. `apply` converts its arguments into
a second `f32` buffer, also of eight, and `min`/`max` accept any count. Raising the first buffer
alone would have let a nine-argument `min` write past the second - in a `ReleaseFast` build,
silently. There is a test for it now, and it is the "check the arguments, not just the calls"
lesson from the jitter arriving in a different file.

Forty warning lines, 25 distinct uniforms, across four packs - and the biome effects those
uniforms gate.

### `CAT_*`, and `PPT_*`, which Iris does not have

    custom uniform 'biome_arid' failed at runtime: UnknownVariable                photon, ten uniforms
    custom uniform 'RW_Temperature_BiomeBias' failed at runtime: UnknownVariable   Kappa, 21; Nostalgia, 2

`IrisDefines.java:30-33` defines `CAT_<NAME>` for each `BiomeCategories` value - the enum name in
upper case, valued by ordinal - right after the `BIOME_*` loop the previous round implemented.
`biomemap.Category` already carried those ordinals; `biomemap.constant` now answers the `CAT_`
spelling too, converting `extremeHills` to `EXTREME_HILLS` at compile time rather than keeping a
second table that could drift from the enum.

`PPT_NONE`, `PPT_RAIN` and `PPT_SNOW` are not in Iris 1.7.3 at all - a grep of the whole zip, Java
and resources, finds nothing. They are OptiFine's names for the three values `biome_precipitation`
takes, and the handoff's claim that Kappa uses them rests on `shaders.properties:356`, which is
commented out; the live rule two lines down is written against `CAT_*`. They are supplied anyway,
because the encoding is the one `BiomeUniforms.java:42-48` reports and a constant that exists can
only make a comparison evaluate that would otherwise be dropped.

One thing checked and not needed: Iris injects these names as textual defines into both
`shaders.properties` and the GLSL sources (`ShaderPack.java:105-107`, `:279`, `:345`), so a pack
could in principle write `#if` against `BIOME_SWAMP` inside a shader. None of the nine does - the
only `BIOME_*` and `CAT_*` names in the corpus's GLSL are the packs' own option macros - so
resolving them in the expression environment is the whole job here. If a pack ever does,
`pipeline.standardMacros` is where they would go.

### `endFlashIntensity` and `endFlashPosition`

    custom uniform 'endFlashFactor0' failed at runtime: UnknownVariable    Complementary, three uniforms

Newer than the 1.7.3 source (nothing in the zip), declared by BSL, Complementary and Solas as a
`float` and a `vec3`. Cubyz has no End, so both are zero constants in `Values`, listed in
`unsupported`, and they exist as fields rather than absences for the reason `lightningBoltPosition`
does: Complementary chains `min(endFlashIntensity, 0.5) * 2.0` through three custom uniforms, and
an unbound name fails the chain where a bound zero evaluates. They leave the coverage lists of all
three packs.

### Bliss's clamp: the shim that cannot be written, and the rewrite that can

    deferred (frag) failed to compile:
    0(2369) : error C1101: ambiguous overloaded function reference "clamp(float, float, int)"

The handoff proposed an exact-match overload shim, `float clamp(float x, float lo, int hi)`, on
the grounds that an exact match wins on every driver. It would, and then it would lose everything
else: this driver hides every built-in overload of a name once a user function carries it. That is
measured, not assumed - `pipeline.probeBuiltinOverloadOnce` does it for `texture` on every load,
and the log's own line 2956 records the result - and `MacroDispatch`'s doc comment says of the
same idea that it "would have taken all four working packs down". Bliss's `deferred` alone has
dozens of other `clamp` calls. So the shim is out, and the handoff's "cannot regress anything" was
the one claim in it this file had already refuted.

What was eliminated for the difference from Iris, in order: the version policy (last round's
hypothesis, confirmed dead by this log - the same four failures at 410 core); the `#extension`
hoisting (the dump has no extension lines at all); and Iris's unused-function removal. That last
one deserves a sentence, because it is the first candidate that is not about the head of the file.
`CompatibilityTransformer.java:178-220` strips every function without a reference, after
preprocessing, before the driver sees the program - a genuine difference in what NVIDIA compiles,
and one a grep for `clamp` and `ambig` could not have found. It does not apply here:
`renderClouds`, the function holding line 444 of `lib/volumetricClouds.glsl`, is called from
`deferred.fsh:289` under nothing but `#ifdef OVERWORLD_SHADER`, and `deferred2`'s call sits under
`VOLUMETRIC_CLOUDS`, on by default. (The other two failures are the `world0/` wrappers:
`composite`'s source is `fogBehindTranslucent_pass.fsh` and `composite3`'s is `composite2.fsh`,
with their calls under `CLOUDS_INTERSECT_TERRAIN`, also on by default.) Iris compiles the same
line. Why it survives there is still not known, and the one measurement that would settle whether
this is the driver or the bridge is Bliss under Iris, in the Minecraft install on this machine.

The fix is `glsl.markIntegerClampBounds`, and its whole justification is that it is a no-op for
any program that compiles today. When one bound of a `clamp` is a float literal, the other bound
has to be a scalar for the call to be valid at all - `clamp(genFType, float, float)` is the only
family a float literal can bind to - so wrapping the other bound in `float(...)` is the identity
for a float and exactly the conversion the driver was asked to infer for an int. It fires on
nothing else: not inside `#define` bodies, where a bound may be a macro parameter with a different
type per expansion; not on a bound of more than one token; not when both bounds are literals or
neither is; and not on an int literal beside an identifier, which may be the integer family. No
type is inferred and the transformer stays a token rewrite. Bliss's line becomes
`clamp(maxIT_clouds / sqrt(exp2(viewPos.y)),0.0, float(maxIT))`.

The harness counts what it touches, per pack, because the rewrite is invisible in the image:

    Bliss 23   BSL 0   Complementary 20   Kappa 16   Nostalgia 10   NRV3 8   photon 54   Rethinking Voxels 8   Solas 0

Every one of those is `clamp(x, 0.0, someFloat)` or its mirror, where `float(someFloat)` is the
identity; the one that matters is Bliss's. Two things would break the argument, and neither is in
the corpus: a pack that defines its own `clamp` (none does), and a `double` bound (the only
`double`s in nine packs are in comments). If either turns up, this rewrite is the first suspect.

### What the coverage lists still name, checked against Iris

The handoff's item 5: every name left in a "nothing supplies" line, grepped as a string literal
across the Iris tree's Java. The rule was its own - anything Iris supplies and the bridge does not
is a gap; anything else is pack-private and correctly zero.

Pack-private, all of them: `isPaleGarden`, `exitWater`, `CriticalDamageTaken`,
`MinorDamageTaken`, `isDead`, `oneHeart`, `threeHeart`, the `sunIntensity`/`skyIntensity`/
`sunColor`/`nsunColor` set, `farPlane`, `textureAtlas`, `cloudWaterTex`, `playerAtlas_sampler`,
`lighttex*`, `voxelimg`, `light_data_sampler`, `combined_*`, `clouds_offset`, `DEBUG_SAMPLER`,
`Moon_Weather_properties`, `imgVoxelMask`, `texBlockData`, `texLpv*`, the `floodfill`, `puddle`,
`wsr` and `vx*` families, and `skyCaptureResolution` again. `velocity` looked like an exception -
`HardcodedCustomUniforms.java:54` registers it, along with `isRainy`, `isSnowy`, `isDry` and a
dozen more that Complementary and Project Reimagined once relied on - but that method has no
caller anywhere in 1.7.3, so Iris does not supply it either. `modelViewMatrix` and
`projectionMatrix` are core-transformer replacements for the fixed-function names, read only by
`gbuffers_line`, which is not run here; already on the do-not-re-litigate list.

One real gap, and the handoff had it filed under "not present". `CommonUniforms.java:168-170`
uploads `dhFarPlane`, `dhNearPlane` and `dhRenderDistance` whether or not Distant Horizons is
installed; without it `DHCompat.java:94-118` answers 0.01, 0.01 and the vanilla render distance
in chunks. The "packs branch on `DISTANT_HORIZONS`" reasoning is true of the branches and not of
the functions: Bliss declares its DH depth helpers outside any guard, 26 reads across ten files,
and whatever calls them sees an unbound zero here where Iris hands over 0.01. All three are
`Values` fields now, the planes as Iris's constants and the radius as Cubyz's render-distance
setting in chunks, which is the same quantity Iris reports and not the LOD-extended `far`. The DH
matrices stay out: nothing in the 1.7.3 tree uploads a uniform under `dhProjection` or its
siblings, so there is nothing to match, and a pack that wants them defines the guard.

### And one the archive check found

The source archive is supposed to build from a clean extract, and the check that says so had only
ever been run as `zig build` followed by `zig build test`. Run as `zig build test` alone, a clean
extract failed with `'mods\renderhook.zig' file_hash FileNotFound`: the archive drops the generated
`mods/*.zig` on purpose, the four feature files came back because `addModFeatures` is called for
the test artifact too, and `renderhook.zig` did not, because only the exe's step depended on the
step that writes it while the engine's test artifact compiles the same root module. Invisible in
the working tree, where the file has existed since the first build. `addRenderHook` returns its
step now and the test artifact depends on it. The archive script lives in
`scripts/build_archives.py` rather than at the end of a transcript, and the check is the last
thing to run before handing an archive over.

### What is verified

`zig build test`: 206 mod tests, 73 engine, in the working tree and on a clean extract of the
source archive. The harness over nine packs: every program transforms, zero leftovers.

And then the driver, the same day (`logs/ts_1788315510914157000.log`, the 21:20 run, every pack
cycled through the picker twice). Against the 15:07 log:

    custom uniform failures      84 lines  ->  0
    programs failing to compile   4        ->  0   (Bliss's chain is 17 passes; it was 13, and no dump was written)
    [error] lines                 6        ->  2   (the two voxel packs declining at load, as designed)
    [warning] lines             141        ->  60  (26 of them the centerDepth readback, as before)
    GL errors                     0        ->  0

`endFlashIntensity` and `endFlashPosition` left the "nothing supplies" lists of BSL, Complementary
and Solas and appear in their documented-constant lines instead, which is where a supplied zero
belongs. The rewrite logged 53 `clamp bound(s) made explicit` lines across the loads. What none of
this says is what any of it looks like: the biome effects, Kappa's weather, and Bliss's clouds are
all rendering for the first time, and no one has described the image yet.

## The first pictures: seven packs, day and night, described

On 2026-09-04 the user put sixteen screenshots in `photos/` at the repository root, a day and a
night view of every pack that loads, taken in one run (`logs/ts_1788565413563858200.log`). This
is the first time anyone has written down what the bridge's output looks like since the
reconstruction, so the record comes first and the diagnoses after it. The mapping of screenshots
to packs is inferred from their timestamps against the log's selection order and the two `/time`
commands the user typed, and could be off by one in the night pass; the user is the authority.

The scene is the same throughout: a sandy hoodoo mesa above a lake, a grass patch on the near
shore, snowy peaks on the far horizon. Kappa and Nostalgia render it correctly by day and by
night - clouds, water reflection, sun and moon, stars - and are the reference for what "right"
means here.

| pack | night | day |
|---|---|---|
| Bliss | the whole frame is fine dark-green speckle; no scene visible at all | sky and sun rays right; terrain dark and green-tinted; the water surface studded with small bright rectangles |
| BSL | very dark, clouds visible, plausible | the whole world pale blue, terrain reading as snow-covered, sky washed out |
| Complementary | black, with a pyramid of shrinking scene copies in the bottom-left corner | the frame is a blurred, darkened copy of the scene, with the same corner pyramid |
| Kappa | correct | correct |
| Nostalgia | correct | correct |
| photon | stars right; the clouds pink; the water a raw cyan, yellow and pink swirl at full brightness | the same water and clouds; terrain fine |
| Solas | the night sky red and full of stars, red reflected in the water; terrain fine | close to right, hazy, no shadows |

The two packs that "do not load and give an error" are Nostalgic Red Voxels and Rethinking
Voxels, declined at load for needing custom images, buffer objects and compute - the feature
under "The ceiling, stated plainly". Solas's missing shadows are its shadow program refused for
`voxel_img`, the same feature per program. Neither is new.

### Bliss: a custom texture that outlived the buffer it stood in for

The speckle is not a lighting failure; it is a texture. Bliss declares

    texture.composite.colortex6 = texture/blueNoise.png

and Iris's rule for that directive is in `ProgramSamplers.java:242-258`: the override for
`colortexN` (and its legacy alias) is *deactivated* for any pass that comes after the buffer has
been flipped at least once, the set restarting with each stage renderer
(`CompositeRenderer.java:96`), and with `final` inheriting `composite`'s. So the name is a
pack-supplied image until the chain writes there, and the buffer itself afterwards. Bliss is
written to exactly that: its first composites dither with blue noise read as `colortex6`,
`composite4` draws `DRAWBUFFERS:06`, `composite7` through `composite9` draw 6, and `composite5`,
`composite8` through `composite11` read the buffer back under the same name. The bridge bound the
noise on unit 6 for every pass of the stage, so every one of those readers got a 512x512 noise
tile in place of its input, tiled across the frame. That is the night picture; by day the scene
is bright enough to show through it.

`Pass.writtenBefore` now carries the set for each pass, resolved at load from the pass list like
the flip bindings, scoped per stage group as Iris scopes it, and `bindOverrides` skips an override
whose buffer is in it. The gbuffers and shadow programs get an empty set, which is what Iris hands
them (`IrisRenderingPipeline.java:334`). The scoping is not academic: photon declares
`texture.composite.colortex0 = image/worley_swirley.dat` and reads that volume in `composite0`
under the name `colortex0` right after `deferred4` drew the scene into the same name, so a set
that spanned the whole chain would have taken photon's first composite down while fixing Bliss.

Whether this is the whole of Bliss is not known. The day picture's dark green terrain and the
bright rectangles on the water may be the same noise reaching the lighting through `composite5`,
or something else; the next launch says.

Two things checked on the way and not the cause. Bliss compares `biome` against *literal* ids -
`in(biome, 6, 52, 7)` for swamps, `in(biome, 23, 24, 25)` for jungles - which this file had said
no pack does outside an OptiFine branch. Those numbers are Minecraft's biome registry order,
which is also how Iris numbers biomes (`MixinBiomes.java:18`, `currentId++` in registry order),
and `biomemap.entries` was built in that order, so 5 is desert, 6 swamp, 23 jungle and 52 lush
caves here too. And photon's `texture.deferred.colortex6.1` is not a sampler called `colortex6.1`:
Iris drops everything after the first dot (`ShaderProperties.java:419`) and, for a raw-format
texture, renames only the declarations of the matching *type* (`:451`), so photon's
`sampler3D colortex6` and `sampler2D colortex6` in the same stage read different things. The
bridge binds the volume on the unit's 3D target, which a `sampler2D` on the same unit never sees,
so the outcome is the same on this driver by a different mechanism.

### The second set: the speckle gone, and the grass that was a cube

A second run the same evening, seven day pictures with the override fix in, and the user's
one-line summary of them: "most of them make the grass block blocky instead of grass and the
water is messed up in some of them." Bliss's speckle is gone, so the override rule was that
picture. Its terrain is still dark with bright green patches, BSL is still blue, Complementary
unchanged, Kappa right - and in Nostalgia, photon and Solas the grass tufts on the near shore
are solid green blocks where Kappa draws plants.

The tuft is `cubyz:grass_vegetation`: `model = "cubyz:cross"`, two crossed quads on a texture
whose empty texels have alpha 0, drawn in the opaque terrain pass. Something has to discard those
texels. Cubyz's own fragment shader does; under OptiFine the fixed-function alpha test did it
after any pack's shader; and Iris, which has no fixed function to lean on, *appends the test to
the pack's `main`* - `CommonTransformer.java:217-222`, the expression from
`AlphaTest.toExpression`:

    if (!(gl_FragData[0].a > iris_currentAlphaTest)) { discard; }

for every non-core fragment program that writes `gl_FragData[0]`, at the reference the program's
`ShaderKey` carries. Every one of the seven packs compiles as `compatibility` or `#version 120`/
`130`, so every one of them gets it. And most of them rely on it: BSL, Nostalgia, Solas and
Complementary have no alpha discard of their own in their terrain program at all, and it is
precisely Kappa (`solid.fsh:286`) and Bliss (`all_solid.fsh:408`), which discard on their own,
whose plants were right. The bridge supplied the *number* - `alphaTestRef`, found missing by
Sundial Lite two sessions ago - and never the test, so a pack that reads the uniform itself was
fine and a pack that expected the pipeline to apply it got a solid cube.

`glsl.Options.alphaTest` appends Iris's test after the pack's renamed `main`, keyed like Iris on
a write to `gl_FragData[0]` or `gl_FragColor`, declaring the uniform only when the pack has not.
Terrain and shadow get it at 0.1; water does not, because `TERRAIN_TRANSLUCENT` carries
`AlphaTests.OFF` (`ShaderKey.java:28`). Found on the way: the bridge's terrain reference was 0.5,
cited to an `AlphaTests.HALF_ALPHA` that does not exist in 1.7.3 - `TERRAIN_CUTOUT` is
`ONE_TENTH_ALPHA` (`ShaderKey.java:27`) - harmless only because Cubyz's opaque alpha is binary,
and gone now so the citation cannot be re-read as a fact. The sky program is left alone:
`SKY_BASIC_COLOR` carries `NON_ZERO_ALPHA`, but the bridge's sky draw does not set the reference
for it and Kappa's and Nostalgia's skies are already right, so that is a separate, deliberate
change if a pack ever needs it.

### The third set: the sampler called `texture`, and the screen on every block

Two more pictures the same evening, Bliss and BSL by day with the alpha test in, and the user's
description of both: "the blocks are showing tiny screens within each one that shows the world."
Which is literally what they show - every block face textured with a small copy of the frame, sky
and horizon included; BSL's is the same thing under a pale blue sky, which is where its blue
came from. The biome line reads `biome=17 (savanna)` from `cubyz:savannah/base` throughout, so
`isCold` was never it.

A block face wearing the screen is a block-texture read that landed on colortex0, and the only
way that happens is the founding bug of this file: a sampler nothing assigned a unit to, reading
unit 0. Bliss and BSL are the two packs whose block sampler is spelled `uniform sampler2D
texture;`, the OptiFine-era name. The bridge's `suppliedSamplers` knew `gtexture`, `gcolor`,
`tex` and `texture0`, and not that one. What it did with `texture` was rename the variable to
`cubyz_textureUnit` "to keep core `texture()` callable" - and then leave the renamed declaration
in place as a `sampler2D`, redirect nothing, and bind nothing to it. Kappa, Nostalgia, photon and
Solas spell theirs `gcolor` or `gtexture` and were never near it.

Iris's rule is in `CommonTransformer.java:229-234`: every use of `texture` and `gcolor` that is
not a function call is renamed to `gtexture`, and from there it is the block texture like any
other spelling. The bridge does that now - `rewrite` maps the variable to `gtexture`, `texture`
is on `suppliedSamplers` so the declaration is stripped and the calls redirected under the pack's
own spelling, and the prologue's existing `#define gtexture cubyz_blockTextures` covers every
mention that survives. No `#define` for `texture` itself, which would swallow the built-in in the
prologue and shim. One guard came with it: an identifier followed by a parenthesis in sampler
position is a call, not a sampler, so `foo(texture(s, uv))` is left alone.

Why nobody saw it before today: Bliss's four post-chain programs did not compile until this
session, so its terrain had never been looked at; and BSL's first pictures were read as a biome
tint, which the biome line then ruled out. The picture that named it was the one taken after
the noise and the cutout were fixed, when there was nothing left in front of it.

### The fourth set: the helper that took the block texture by hand

With `texture` redirected, BSL rendered ("the other works I think") and Bliss failed to compile:

    gbuffers_terrain (frag) failed to compile:
    0(1788) : error C1102: incompatible type for parameter #1 ("sampler.211")

The dumped line is `texture2D_POMSwitch(gtexture, adjustedTexCoord.xy, vec4(dcdx,dcdy), ifPOM,
textureLOD)`, and the helper is `vec4 texture2D_POMSwitch(sampler2D sampler, ...)`. Under Iris
the block texture is a `sampler2D` and that is a plain call; here `gtexture` is now the array,
and the array cannot go into a `sampler2D` parameter. This is the exact shape "Known limits"
records for Complementary's `textureAF` as a wall - the pack passing the sampler into its own
helper, "type inference across a call graph rather than a token rewrite". The previous round
had walked Bliss straight into it: before, its `texture` was a `sampler2D` reading the screen,
which compiled and was wrong; after, it was the array, which was right and did not compile.

It is not a wall for a helper that only ever samples its parameter, and Bliss's does exactly
that - one `texture2DGradARB` and one `texture2D` with a bias, both on the parameter. The bridge
already dispatches on sampler *type* for macro parameters, where the sampler is unknowable at
rewrite time and the compiler is asked to choose; a function parameter is the same situation one
level up. So `glsl.SamplerFunction`: every global-scope function with a `sampler2D` parameter is
found; if every use of that parameter in the body is the first argument of a sampling call the
transformer knows, the body's calls on it are routed through the `cubyz_sampleAny` family and the
function is emitted twice, once as written and once with `sampler2DArray` for those parameters.
The overload's prototype is placed on the definition's own line, so it is declared before every
caller and no line number moves; its body goes after the pack's source. Overload resolution then
does the rest: `texture2D_POMSwitch(gtexture, ...)` lands on the array copy and
`texture2D_POMSwitch(normals, ...)`, four lines later in the same program, on the original.

The boundary is deliberate. A helper whose parameter meets `textureSize`, arithmetic, or another
function is left alone, because the array copy would not compile and a dead overload that fails
still fails the program. `textureAF` is exactly such a helper, and it stays a known limit - with
the entry there updated to say why. The harness runs the geometry programs with the gbuffers
builder's own options now, rather than the plain ones, and reports how many were overloaded per
pack; all nine transform, and every pack has two or three such helpers, most of them shadow and
noise readers that are overloaded harmlessly and never called with the array.

Two things this cannot do yet, both recorded rather than pretended: a prototype declared ahead
of a qualifying definition only gets its overload prototype if the parameter count matches, and
a pack whose parameter is itself spelled `texture` would collide with the block-texture define
after the rename. Neither is in the corpus.

### The fifth set: Bliss renders, and its lake is black

Bliss's terrain compiled and drew - real block textures, plants, shadows, the sky and its clouds
- and the user's next line was "water is like black in bliss". The picture agrees: a dark
grey-brown surface with waves in it and nothing reflected. And the same log had a second thing:
Complementary's terrain now failed, `undefined variable "spriteBounds"` seven times, from the
copy of `textureAF` the overload feature had appended - outside the `#if ANISOTROPIC_FILTER > 0`
block the original lives in, in a configuration where that block, and every global it declares,
is not compiled at all. The copy has to be dead exactly where the original is: each overload now
replays the `#if`-family lines enclosing its definition before its body and closes them after,
an `#else` or `#elif` entry replaying its `#if` first. Tested on that shape.

The black water is an ordering error, and not a small one. The bridge ran the whole post chain
after all geometry: shadow, prepare, opaque terrain, the engine's own draws, water, and then
deferred, composite and final together. Iris does not. `IrisRenderingPipeline.beginTranslucents`
(`:1052-1078`) copies the pre-translucent depth, runs every deferred pass, and only then lets
translucent geometry draw; `composite` and `final` follow the whole world
(`finalizeLevelRendering`, `:1083`). The translucent programs are built against the flip state the
deferred passes leave (`flippedAfterTranslucent`, `:317`). Packs are written to that order, and
what it means for water is concrete: Bliss's `deferred1` renders the sky into colortex4 and its
water reflects that buffer; Complementary's `deferred1` is the lighting pass, and its water
refracts and depth-tests against a lit scene; photon's translucent pass reads the sky map and fog
its deferred stage produced. Drawn first, Bliss's water reflected a buffer nothing had written yet
this frame - that is the black lake - and every other pack's water was composed over an unlit
G-buffer and then lit as if it were opaque.

`beginTranslucent` now runs the deferred passes after the depth snapshot and before the water
draw, when the pack's own terrain program is drawing - the one case where the G-buffer and depth
are complete at that point. Without a terrain program the scene is only imported at post-chain
time, so deferred waits for it as before. The water pass writes the side the first post-deferred
pass reads, by the same inversion the gbuffers side uses, and `runPostChain` skips what already
ran. The engine's own draws between terrain and water - entities, item drops, block entities -
still land before deferred, which is also where Minecraft's do. One consequence for the
diagnostics: the "colortex0 after the gbuffers stage" thumbnail is now taken after deferred.

This was found by reading Bliss's water for what it reflects, and it is the kind of thing the
handoff warned about: a frame order stated in this file - "shadow, prepare, gbuffers, deferred,
composite, final" - that was true as a list and wrong about where the translucent draw fell in it.

### The sixth set: still dark, and the directive nothing read

With deferred in its place, Bliss's lake was "still super dark", and "the sky is light but the
landscape is like super dark from shadows pretty much everywhere". The one picture faces the sun
across the lake - `vDotL=0.936 (facing the sun)`, `sunAngle=0.087`, the same early-morning time
as the lit picture two rounds earlier, which faced the other way. Everything the camera sees is
the shadow side of the terrain, under Bliss's fog, with one lit strip of sand where the sun gets
between the hoodoos. How much of that darkness is Bliss at sunrise and how much is the bridge is
not decidable from a final frame, and it is not decided here. The water is decidable: a lake
facing a low sun has a glint, and this one has none and reflects nothing.

What reading found on the way is a gap of the reconstruction's own shape. Bliss's water takes
its sky reflection and its ambient light from the sky map in colortex4 -
`skyCloudsFromTexLOD2(normal, colortex4, 6)` - at mip level 6, under
`const bool colortex4MipmapEnabled = true;`, and Complementary's `composite4` mipmaps colortex0
for its bloom the same way. `pack.parseMipmapEnabled` read those directives, correctly, and had
no caller. Iris (`CompositeRenderer.java:177-201`, `:255-260`) regenerates the chain of each
named buffer's *read side* just before the pass and switches its filter to mipmapped, then puts
every filter back at the end of the frame (`FinalPassRenderer.java:180-193`, `:274-277`). The
bridge does that now, per pass, from the fragment source. It is not the black water: a level-6
read of a texture with no chain falls back to level 0 under a plain filter, sharp rather than
black. It is a fidelity gap that was there all along, and the ambient it feeds is one of the
two things this picture is about.

Also on the way: integer-format buffers were allocated with a linear filter, which GL treats as
an incomplete texture that reads zero; nearest now, as Iris does. Nothing in the seven loading
packs declares one, so nothing visible changes.

For the water itself nothing offline survives. The reflection needs `isEyeInWater == 0`, the
sky map in colortex4 on the side the water reads, and the water's own output in colortex2
reaching `composite3`; each of those is right on paper and one of them is not right on the
driver. The G-buffer view answers which in three screenshots, and that is the ask.

### What the other two need

**Complementary.** From composite5 onward the pack carries its finished frame in `colortex3`
(`composite5.glsl:236` writes the composed scene there under `DRAWBUFFERS:3`, `final.glsl:98`
reads it back), and the bloom tiles composite4 builds live in that same buffer's corner. The
screen shows the buffer as composite4 left it. The ping-pong bookkeeping was checked against that
exact sequence and is right on paper - composite4 writes alt, composite5 reads alt and writes
main, composite6 main to alt, composite7 alt to main, final reads main - so the fault is in what
the passes actually bind or draw, not in the parity, and the G-buffer view of colortex0 and
colortex3 is the instrument.

**photon's water and Solas's sky** have no hypothesis yet that survives reading. The water is
plainly a worley pattern; Solas's night sky is its Milky Way (`lib/atmosphere/milkyWay.glsl`),
which samples `noisetex` and the `gaux4`/`depthtex2` galaxy image, in a colour it should not have.
Both are geometry-or-post questions the G-buffer view answers in one look.

## The seventh set: a regression from the alpha test, and three rules Iris keeps that this file had wrong

The run of 2026-09-04 22:46 (`logs/ts_1788579983684593800.log`, 5022 lines) and the eight
screenshots in `photos/` taken during it, the user's summary being "many of the shaders are
entirely broken, after a few new updates it regressed some shaders visuals". The pack order in the
log is Bliss, BSL, Complementary, Kappa, Nostalgia, photon, Solas, and the pictures read, in time
order: Bliss twice, hazy, its mesa faces speckled with white points and the water studded; a pale
blue-white world with the block textures showing through, which is BSL; the whole frame a blurred,
darkened copy of the scene with a pyramid of shrinking scene copies in the bottom-left corner,
which is Complementary as before; a white blow-out with streaks and the "game encountered errors"
dialog; a black world with a white lake; and black terrain with pink patches, rainbow water and
the dialog again. The last three are Kappa, Nostalgia and photon, and the log says why they look
like nothing this file has described before.

### Kappa, Nostalgia and photon stopped linking

    [error]: irisbridge: gbuffers_terrain failed to link:
    Fragment info
    -------------
    (0) : error C3001: no program defined
    (0) : error C3001: no program defined
    ...

for `gbuffers_terrain` and `shadow` in exactly those three packs, 856 such lines in the run, the
4096-byte info-log buffer filled with one message repeated. Both stages compiled - a compile failure
logs and dumps, and neither happened - so the fragment stage the linker saw had no `main`. It did
not. "The second set" above added Iris's alpha test: `glsl.transform` renames the pack's `main` to
`cubyz_packMain` whenever `entryPointName` is given and appends a `main` wrapper that calls it and
discards on alpha - but the wrapper only where Iris puts one, a write to `gl_FragData[0]` or
`gl_FragColor` (`CommonTransformer.java:218`, `replaceIndexesSet.contains(0L)`), while the rename
happened regardless. Kappa, Nostalgia and photon are the three packs whose gbuffers fragment stages
write their own `out` variables, so they got the rename and no wrapper: a fragment stage that
compiles and has no entry point. The two packs this file calls the reference for what "right"
means were the ones broken, and that is the regression the user saw.

The first run after that change (`ts_1788565413563858200.log`, the sixteen screenshots) did not
show it because Kappa and Nostalgia were selected before the alpha test went in that evening; the
22:21 run was the first to load them after it. The rename now depends on the wrapper: `transform`
decides `appendsAlphaTest` first and renames a fragment stage's `main` only when it is true, the
vertex and geometry stages keeping their rename because their prologues always supply the `main`
that calls it. The unit test for the core-profile case, which had only asserted that no `discard`
was added, now asserts that `void main()` survives and `cubyz_packMain` does not appear; the
harness counts fragment stages that define no `main` after the transform, and with the fix
removed it flags exactly Kappa's `shadow.fsh` and `gbuffers_terrain.fsh`, so the instrument
catches the thing it was built for.

### Directives are read from the live branch, as Iris reads them

Complementary's `composite4`, the bloom-tile pass, ends

    /* DRAWBUFFERS:3 */
    gl_FragData[0] = vec4(blur, 1.0);

    #if MOTION_BLUR_EFFECT == 1
        /* DRAWBUFFERS:30 */
        gl_FragData[1] = vec4(color, 1.0);
    #endif

with `#define MOTION_BLUR_EFFECT -1 //[-1 1]`. The loader took the last directive in the file,
`30`, attached colortex0 as a second draw buffer, and the shader never assigned that output. What
an unassigned output writes is undefined, and on this driver it was the value of output 0, so
colortex0 - the scene, which `composite5` reads and tonemaps into the finished frame - became a copy
of the bloom tiles: a pyramid of shrinking scene copies in one corner over black, then bloomed, which
is a blurred darkened scene spread across the frame. That is the Complementary picture, in every
set since the first, and "What the other two need" above was looking for it in the ping-pong
parity, which was right.

The rule this file stated - "neither this loader nor Iris evaluates those conditionals, so
last-wins is what makes the wider set the one that gets mapped" - was wrong about Iris.
`ShaderPack.java:286` runs a C preprocessor (`JcppProcessor.glslPreprocessSource`, comments kept)
over every program before the `ProgramSource` exists, so the text `CommentDirectiveParser` searches
holds only the live branch of every `#if`, and the same is true of the `const` declarations
`ConstDirectiveParser` reads. Last-wins over that text is right; over the raw text it also picks up
directives in branches the pack's options have switched off. `pack.loadProgram` now reads every
directive from `liveView`, the source run through `preprocess.run` against Iris's environment - the
standard macros and the feature flags, no option values, since those are the `#define` lines in the
source, already rewritten by `options.apply` - and keeps the raw text only as a fallback when the
live view has no directive at all, which it logs. The compiled source is still the pack's own text,
which the driver preprocesses for itself. `parseSettings` and `parseMipmapEnabled` read the same
view, so a `colortexNFormat` or a `MipmapEnabled` in a dead branch no longer counts either, and
`Program.mipmappedBuffers` is resolved by the loader rather than re-read from the raw text in
`pipeline.buildPass`.

Two things the preprocessor could not do before this, both needed on the first pack: a directive
line's trailing comment - every option a pack declares carries one, `#define X -1 //[-1 1]` - made the
value unparseable and so 0, and a macro defined as another macro (`#define A B`, `#define A (B + 1)`)
read as 0 rather than as B. `directiveArgument` cuts the comment and `Evaluator.expandMacro`
evaluates a non-literal value as an expression, sixteen levels deep at most.

The harness now compares each program's raw-text directive against the live one and prints every
difference, and there were thirty-nine across the nine packs. The ones that reach the screen:

| pack / program | raw text | live | what it did |
|---|---|---|---|
| Complementary `composite4` | 3, 0 | 3 | the pyramid, above |
| Complementary `gbuffers_water` | 0, 3, 4, 8 | 0, 3 | colortex4 and colortex8 got undefined values over every water pixel |
| BSL `gbuffers_terrain` | 0, 3, 6, 7 | 0 | colortex3, 6 and 7 got undefined values over every terrain pixel |
| BSL `gbuffers_water` | 0, 1, 6 | 0, 1 | colortex6 likewise |
| BSL `deferred1`, `composite0`, `composite5` | 0 4 5 6; 0 1 5; 1 2 9 | 0 4 5; 0 1; 1 2 | one extra buffer each, undefined |
| photon `gbuffers_water` | 13 | 3, 13 | `refraction_data`, output 0, landed in colortex13 where the pack keeps its translucent colour, and `fragment_color` was dropped - the raw cyan, yellow and pink swirl on the water |
| photon `gbuffers_terrain` | 1, 2 | 1 | `gbuffer_data_1`, undefined, into colortex2 |
| Solas `gbuffers_terrain` | 0, 3 | 0, 3, 6, 7 | `GENERATED_SPECULAR` is on, so the terrain writes four outputs and only two were attached: no normals and no fresnel reached its lighting |
| Bliss `composite3` | 0 | 0, 14 | the `CLOUDS_INTERSECT_TERRAIN` output was dropped |

Kappa and Nostalgia move nothing, which is consistent with their being the two that rendered right.
The others' pictures are not all explained by this - BSL's paleness and Bliss's speckle have no
proof yet - but each row is a buffer that was being written with undefined data every frame, and
none of them can be reasoned about until that stops.

### `shaders.properties` is read with the option set, as Iris reads it

Iris reads its properties files through the same C preprocessor with the environment macros and
every option's value in the table (`PropertiesPreprocessor.java:29-51`): a boolean option that is on
is a defined name, one that is off is not defined at all, a valued option carries its value. The
values come from the shader sources - `ShaderPackOptions` is built from the include graph before
`ShaderProperties` is read (`ShaderPack.java:151-175`). The bridge fed that pass the environment
and the *user's overrides* only, so every `#if` on a pack default took the branch an undefined name
takes, and a boolean override to `false` was put in as a defined name, which `#ifdef` reads as on.

Here the sources cannot simply be read first: the user's `profile=` in the options file names a
preset declared in shaders.properties, and its values have to reach the sources before the options
are discovered from them. So `load` reads the file twice. The first pass sees the environment and
the overrides and supplies only the feature flags and the profiles, neither of which is declared
under an option in the corpus; the programs are then loaded, the option set is discovered from
their rewritten sources (`declaredOptionsOf`), and the second pass - through
`options.putDefines`, Iris's shape - is the one every later reader gets, `block.properties`
included, since Iris's `IdMap` uses the same table. `loadPrograms` no longer reads
`program.<name>.enabled` itself; `pack.applyEnabledFlags` does, after the second pass. The
harness reads the file both ways and prints every key that differs:

- **Solas**: `texture.deferred.depthtex2 = tex/milkyWay.png` is under `#ifdef MILKY_WAY`, on by
  default in `lib/common.glsl:309`. Without it the deferred stage sampled the real `depthtex2` as
  its galaxy image - a depth buffer, near 1.0 in the red channel across the sky - which is the red
  night sky full of stars and its red reflection in the water. "What the other two need" had this
  down as a geometry-or-post question; it was a texture binding.
- **photon**: `size.buffer.colortex9 = 0.25 0.25` and colortex10 likewise are under
  `#if CLOUDS_TEMPORAL_UPSCALING == 4`, the default in `settings.glsl:194`. The log's declared
  sizes for photon listed colortex4, 6, 7, 8 and 14 and not these two, so its low-resolution cloud
  passes wrote and read screen-sized buffers with maths written for a quarter of that.
- **Bliss**: `program.world0/deferred2.enabled = false` is under `#ifdef CLOUDS_INTERSECT_TERRAIN`,
  a bare `#define` in `dimensions/composite1.fsh:175` that Iris counts as a boolean option because
  the same logical file tests it with `#ifdef` (`OptionAnnotatedSource`), and it is on. The bridge
  ran `deferred2 draws 0` in every Bliss frame - a cloud pass the pack had switched off in favour of
  the one in `composite1` - and, in the same file, nineteen `uniform.*`/`variable.*` declarations
  under `SWAMP_ENV`, `JUNGLE_ENV` and the health and lightning options never reached
  `customuniforms`: `isSwamps`, `isJungles`, `sandStorm`, `snowStorm`, `lightningFlash`,
  `exitWater`, the damage chain.
- **Kappa**: four `RW_BIOME_*` variables under `RFOG_SB_FogWeather`, the fog's biome inputs.
- **Complementary**: `blend.gbuffers_weather.colortex12 = off` and `shadowBlockEntities = false`,
  neither of which reaches Cubyz; its `program.*.enabled` gates on `SHADOW_QUALITY == -1` and
  `FXAA_DEFINE == -1 || FXAA_STRENGTH == -1` had been right only because an undefined name reads
  as 0 and neither default is -1.
- **Bliss, BSL, photon**: `shadowEntities = false` and `shadowBlockEntities = false` were being
  taken from under `#ifndef RENDER_ENTITY_SHADOWS` and its equivalents, options that are on; Iris
  keeps entity shadows for all three. Nothing here draws entities into the shadow map yet, so this
  changes nothing visible.

### Smaller things found on the way

- `colortexNClearColor` was parsed by nothing, and Iris's default clear for colortex1 is solid
  white, not black (`ClearPassCreator.java:34-43`). Kappa asks for `vec4(0.0, 1.0, 0.0, 0.0)` on
  colortex15 and reads its `.y` as the ambient occlusion term (`sspt.fsh:564`), so every pixel
  nothing drew was fully occluded rather than open. `pack.Settings.colortexClearColor`,
  `targets.defaultClearColor`, `Target.clearColor`; colortex0 stays black with alpha 1, since the
  sky import or the pack's own sky covers it before anything reads it.
- `pipeline.standardMacros` appended its fixed list twice, so every generated shader carried its
  `MC_*` block twice - legal, since the redefinitions were identical, and the reason the dumps look
  the way they do. Once now.
- The load log said "profile disabled program composite" for BSL's composite2 and composite3,
  which reads as the chain's first composite being off. The line carries the index now.
- The boolean-override-as-defined-name bug in the properties preprocessing, above, is fixed in
  `putOverrideDefines` for the first pass; the second pass never had it.

### What is verified, and what is not

`zig build test`: 220 mod tests and the engine's 73. The harness: all nine packs transform, zero
leftovers, zero stages without `main`, and it prints the thirty-nine moved directives and the
option-decided keys per pack so the next change that touches either shows up as a number. The
release builds.

Nothing above has been seen on the driver. The next launch should cycle every pack through
`Settings -> Shaders` and the things to look at are, in order: Kappa and Nostalgia back to the
reference pictures; Complementary without the corner pyramid and with a sharp frame; photon's
water no longer a colour swirl and its clouds no longer pink; Solas's night sky no longer red; and
then, with those gone, whatever is left of BSL's pale world and Bliss's speckled mesa, which are the
two pictures nothing in this section explains.

## The eighth set: a lightmap in the wrong units, and a buffer that was never cleared

The runs of 2026-09-05 00:01 and 00:03 (`logs/ts_1788584283334956400.log`,
`logs/ts_1788584551098388600.log`), the first launches with the seventh set's fixes in. Both are
clean: zero `[error]` lines except Rethinking Voxels declining at load, no link or compile
failures, Kappa and Nostalgia loading again. The user's report, in their words: "the clouds make
the terrain almost entirely black because the clouds are making shadows that cover everything in
bliss and photon", "in bliss when i load it at first the screen turns red and so i have to resize
the window for it to fix", "in photon there is a weird separate shadow glitch or darkness glitch
where the light on the ground only shows where i am and so if i fly up high its like just dark
everywhere on the ground", "the water is super dark in a lot of the shaders", and "rethinking voxels
just flat out does not load".

### The lightmap coordinate was in the wrong units for two packs

The three darkness reports are one bug, and it names its own packs. Iris hands a vertex program
`gl_MultiTexCoord1 = vec4(iris_UV2, 0.0, 1.0)` (`VanillaTransformer.java:45`), where `UV2` is
Minecraft's raw lightmap coordinate - light level times sixteen, 0..240 per axis - and supplies
`gl_TextureMatrix[1]` as the `LightTexture` transform, scale 1/256 plus 1/32
(`BuiltinReplacementUniforms.java:12`), which turns 240 into 31/32, the texel centre of the
lightmap's top row. The bridge emitted the *final* coordinate, `skyLight*0.9375 + 0.03125`, with an
identity texture matrix. That is exactly right for a pack that multiplies by the matrix, and every
pack but two does: Kappa, Nostalgia, BSL, Complementary and Solas all write
`(gl_TextureMatrix[1] * gl_MultiTexCoord1).xy`. Bliss writes `gl_MultiTexCoord1.xy / 240.0`
(`all_solid.vsh:215`, and the same in its translucent and particle programs) and photon writes
`clamp01(gl_MultiTexCoord1.xy * rcp(240.0))` (`gbuffers_all_solid.vsh:97`, translucent, basic,
shadow). Both read a sky light of 0.968/240 - four thousandths - at every vertex in the world.

What that does to photon is the disc. Its shadow term inside the shadow map's range is the shadow
map; past `shadowDistance` it fades to the lightmap
(`include/lighting/shadows/common.glsl`, `get_shadow_distance_fade` into `get_lightmap_shadows`,
which is `smoothstep(13.5/15, 14.5/15, skylight)`), so the ground was lit where the shadow map
reached and read as fully shadowed beyond it; flying up puts every visible surface past that
range, and the whole ground goes dark. Its sky ambient is scaled by the same value, and so is its
water's lighting, which is the dark water. In Bliss the sky light gates the indirect light and the
water's ambient (`all_translucent.fsh:639`, `Indirect_lighting = skyCloudsFromTexLOD2(...)` under
the lightmap), so its terrain and its lake went black under what looked like the cloud shadows
the pack does draw. That lake is the one "The fifth set" and "The sixth set" chased through the
frame order and the mipmap directive; both of those were real, and neither was this.

The prologue now emits the raw coordinate, `vec4(torchLight*240.0, skyLight*240.0, 0.0, 1.0)`
(`prologue.terrainVertex`, and `vec4(0.0, 240.0, 0.0, 1.0)` for the sky), and `uniforms.zig`
uploads `lightmap.lightmapTextureMatrix` in slot 1 of `gl_TextureMatrix` for every program,
gbuffers and fullscreen alike, as Iris does for any program that names it. The first group of
packs comes out exactly where it was; the second gets a light level. `lightmap.zig` pins the matrix
with a test and `prologue.zig` pins the raw range.

Found by reading photon's shadow code for what it does past the shadow distance, then grepping the
corpus for how each pack reads `gl_MultiTexCoord1`. The crosshair light probe in the same log
reading `sun=(0,0,0)` a hundred blocks out was a distraction: that is Cubyz's own light at a shaded
cliff face, and the packs never saw it.

### Bliss opened red until the window was resized

`RenderTargets.updateSize` allocates every colortex with `glTexImage2D(..., null)`, which is
whatever the driver had in that memory, and `clear` honours `colortexNClear = false` from the first
frame. Bliss declares that for colortex1, its G-buffer, so on the first frame the pack read a
buffer nothing had ever written - red, on this driver, on this day - and every frame after was
built on the previous one. A resize reallocated it into memory that happened to be clean. Iris
never lets this happen: `isFullClearRequired` is set on creation and on every resize, and the
`fullClear` variant of `ClearPassCreator` then clears every buffer once, `Clear = false` included
(`IrisRenderingPipeline.java:951-956`). `RenderTargets.fullClearPending` does the same: set by
`updateSize`, consumed by the next `clear`, which that once ignores the per-buffer flag. The
history a pack accumulates is lost on a resize, which is also what happens under Iris.

### What the water still is

With the lightmap right, the remaining question about water is its colour, and that is a judgement
this file already records rather than a defect: `cubyz_applyVertexTint` hands the water program a
`glColor` of Cubyz's absorption cubed, (0.18, 0.54, 0.83) for `water_absorption.png`'s
(144, 208, 240), because packs read `glColor` as the tint of everything seen through the surface.
Minecraft's water texture is a light grey that the tint colours; Cubyz's `water.png` is already
dark blue, (21, 99, 163) on average at alpha 0.42, so a pack that draws `texture * glColor` gets the
colour applied twice and a surface darker and more saturated than Minecraft's. Kappa and Nostalgia
rendered their water right under this, so it is not what "super dark" was; it is what is left to
look at if water is still too dark once the sky light reaches it.

### Rethinking Voxels

Declined at load, as before and as intended: `iris.features.required = CUSTOM_IMAGES SSBO
COMPUTE_SHADERS`, and the bridge implements none of the three. Iris refuses such a pack too
(`ShaderPack.java:196`). It is "The ceiling, stated plainly": one feature with three parts, well
specified by the packs, and the largest piece of work left in this project. Nothing in this set
changes it.

### What is verified, and what is not

`zig build test`: 222 mod tests and the engine's 73. The harness is unchanged from the seventh set.
Nothing above has been seen on the driver. The next launch should look at Bliss and photon first -
terrain lit under an open sky, the ground lit at every distance in photon, and both packs' water -
then Bliss's first frame with no resize.

## The ninth set: Bliss's lake, twice over

One screenshot, taken with the eighth set in: Bliss by day, the sand and the mesa lit and shadowed
correctly, the sky bright, and the lake a flat dark teal with wave normals visible in its shading
and no sky in it anywhere - not even at the far shore, where a water surface at a grazing angle is
almost pure reflection. "i think the bliss water is too dark." Two causes, both in the prologue's
material path, both measured rather than guessed.

### The synthesised specular said the water was rough

Bliss's water starts from a hardcoded material, `specularValues = vec2(1.0, 0.02)` - perfectly
smooth, F0 of 2% - and overrides it with the specular texture whenever that texture says anything:
`if(SpecularTex.r > 0.0 && SpecularTex.g <= 1.0) specularValues = SpecularTex.rg;`
(`all_translucent.fsh:727`). Under Iris with no resource pack the specular texture is Iris's default
for a block with no `_s` map, `0x00000000` (`PBRType.SPECULAR`), so the override never fires and
the hardcoded mirror stands. The bridge synthesises LabPBR from Cubyz's own material arrays,
`cubyz_labPbrSpecular`, and put Cubyz's reflectivity in the smoothness channel: for
`water_reflectivity.png` that is 27/255, 0.106. Bliss took it at its word:
`roughness = pow(1.0 - 0.106, 2.0) = 0.8`, and its reflection gate,
`visibilityFactor = exp2(-4 * roughness^3 / f0)`, came out at 2^-19.3, about 1.5e-6. Every
reflection off - sky, screen-space and the sun glint, which went through the same roughness - and
what was left was the lit albedo alone.

The mapping was wrong about Cubyz, not just about Bliss. Cubyz has no roughness:
`chunk_fragment.frag` samples a perfect mirror, `fixedCubeMapLookup(reflect(direction, normal))`,
and scales it by reflectivity. That is a perfectly smooth surface whose *reflectance* is the value.
So the translation is smoothness 1.0 wherever reflectivity is non-zero and F0 from the value, and
zeros - Iris's default texel - where it is zero, which is every block without a reflectivity
texture: 91 of them have one, the metals, gems, glass, ice, lamps and water, all in the 0.01 to
0.2 range. Bliss now reads `(1.0, 0.106)` for water: a mirror at 10.6%, a little more reflective at
normal incidence than the 2% it hardcodes, which is what Cubyz says the water is.

### The water was coloured twice

The second is the judgement "What the water still is" recorded a set ago, now acted on because the
numbers say it is not small. Minecraft's `water_still.png` is a light grey and the biome tint in
`glColor` colours it; a pack draws `texture * glColor`. Cubyz's `water.png` is already dark blue,
(21, 99, 163) on average at alpha 0.42, and `cubyz_applyVertexTint` handed the pack a blue `glColor`
beside it - the absorption cubed, (0.18, 0.54, 0.83) - so the product was (0.015, 0.21, 0.53) where
Minecraft's is about (0.19, 0.36, 0.70): red twelve times darker, green and blue at half and three
quarters. Bliss then takes `Albedo *= sqrt(luma(Albedo))` for water, which compounds it.

The tint cannot simply go white, because packs read `glColor` a second time as the colour of
everything seen through the surface (Bliss's `GLASS_TINT_COLORS`, the riverbed's tint), which is
the reason the tint exists. So the two engines' conventions are translated per block class. A fluid
gets Minecraft's pair: the tint in `glColor`, and its texture divided by that tint on the fragment
side - `cubyz_textureUntint`, a flat varying the vertex stage writes as the tint's reciprocal and
every block-texture helper in `terrainFragment` multiplies by - so `texture * glColor` is exactly
the colour Cubyz authored, (0.083, 0.387, 0.639), and the through-water tint is unchanged. A
translucent block that is not a fluid is Minecraft's stained glass: the colour is in the texture and
`glColor` is white, so it gets neither tint nor untint; before this Cubyz's dyed glass was coloured
twice too. The varying rides through a pack's geometry stage beside the texture layer
(`geometryPassthrough`), the untinted vertex prologue writes it as 1.0 so the fragment stage never
reads it unwritten, and the material synthesis reads the reflectivity array directly and is
untouched by it.

### What is verified, and what is not

`zig build test`: 224 mod tests and the engine's 73; the prologue tests pin the smoothness rule, the
untint in both prologues and its passage through the geometry stage. Not seen on the driver. The
next Bliss picture of the lake should show the sky in it, a sun glint, and a surface colour that is
Cubyz's own blue rather than the near-black; the other packs' water should be brighter by the same
factor wherever they use the texture, and unchanged where they use their own water colour.

## The tenth set: three reports, two of them not yet located

The run of 2026-09-05 00:52 (`logs/ts_1788587576723089700.log`, clean, at 1920x1009 after the user
maximised the window), and the report on it, in the user's words: "water is still pretty dark in
most shaders and kappa and nostalgia lighting messed up as in places on a higher elevation than
eye view are weirdly dark compared to below eyeview and also grass is light form a distance and not
impacted by shadows as much". No picture this time. What follows is what could be settled from the
log and the sources, what was changed on that basis, and what a measurement has to decide.

### What the log settled: Bliss's health chain, and a boolean that was an int

    custom uniform 'interpolatedHealth' failed at runtime: TypeMismatch
    custom uniform 'smallHealthDifference' failed at runtime: UnknownVariable
    ... largeHealthDifference, MinorDamageTaken, delayedCritDamage, CriticalDamageTaken

These are the six Bliss declarations the option-aware properties pass brought in ("The seventh
set"), and the first of them is `smooth(if(is_hurt, 0.0, Currenthealth), 0.0, 1.0)`. Iris declares
`is_hurt` with `uniform1b` - it is one of twelve booleans, `hideGUI`, `isRightHanded`,
`is_sneaking`, `is_sprinting`, `is_hurt`, `is_invisible`, `is_burning`, `is_on_ground`,
`firstPersonCamera`, `isSpectator`, `hasCeiling`, `hasSkylight`, every `uniform1b(` call in
`CommonUniforms.java` and `IrisExclusiveUniforms.java` - and the bridge's `Values` keeps them as
`i32`, which is right for the GL upload and wrong for the expression language, where an int in
`if`'s condition is a type error. `customuniforms.builtinValue` now types those twelve as booleans
(`booleanUniforms`); the five that chained off the first failed only because it had.

### The water: one more unit conversion, and one thing not to conclude yet

Two facts about the water were measurable without a launch. The first is the alpha. Minecraft's
`water_still.png` is about 0.70 opaque, 178 of 255, and every pack composes its water surface
against that: Bliss weights the water's own colour by the texel alpha and lets the remainder be the
refracted bottom, and the vanilla-texture paths of the others do the same. Cubyz's `water.png` is
0.42, so more than half of every water pixel was the lake bed, which is dark wherever the water is
deep. The fluid untint from the ninth set now carries an alpha floor beside the colour factor
(`cubyz_textureUntint.a`, `cubyz_minecraftWaterAlpha = 178/255`, applied in `cubyz_untint` as
`max(texel.a, floor)`): a fluid's texture reaches the pack at Minecraft's opacity, and nothing
else is touched. This is the same class of judgement as the tint and the untint - Cubyz's own
transparency is what Cubyz's own shader still draws - and it is recorded here so it can be reverted
in one constant if the packs' water turns out to want the thinner surface.

The second fact is a warning against the obvious next fix. The crosshair light probe in the
previous run read Cubyz's own sun light as `(255,255,255)` at 42 blocks and `(0,0,0)` at 109, the
second at a pitch of -6.6 degrees from eye height 80.7, which lands the sample around lake level.
`centerDepth` is taken before the water is drawn, so that 109 blocks is the lake bed and the "air"
sample half a block in front of it is inside the water. Cubyz attenuates sun light through water at
9, 5 and 1 per block plus 8 per step below full, so a deep bed does read near zero in its red
channel - but so does Minecraft's, which loses a level per block of water, and packs render a deep
lake bed dark under Iris too. Whether the bed here is darker than it should be is a question for the
probe, not for another change: with `Settings -> Shaders -> Log diagnostics` on and the crosshair
on deep water, the `crosshair light` line says what the bridge hands the pack for that bed.

### Kappa and Nostalgia above eye level: not located

Every change since the two packs last rendered right was checked against them and eliminated on
paper. The lightmap now travels as the raw 0..240 value with the 1/256 + 1/32 matrix, and both
packs multiply by the matrix, so their `uv[1]` is the same number to the last bit; the matrix
reaches only gbuffers programs, since no post-chain program in the corpus names
`gl_TextureMatrix[1]`. The shadow lookup is self-consistent with the bridge's matrices: Kappa
compresses depth by 0.2 against `shadowmapDepthScale = 512/0.2`, which is the bridge's ±256 range
exactly, and the ortho is symmetric about the player. The cloud shadow map, `readCloudShadowmap`,
projects by position only. The resize to 1920x1009 propagates to `viewWidth`, `viewHeight`, the
targets and the depth copies alike. The colortex1 white default touches only pixels nothing drew,
and Kappa's colortex15 clear colour only pixels outside its downscale viewport. Nostalgia had no
option-decided keys; Kappa gained four `RW_BIOME_*` fog inputs, which in this savanna set its
sandstorm term to 0.6 - a haze the pack applies at low altitude, which would brighten the ground
below the eye against terrain above it, and would wash shadows out with distance. That is the one
hypothesis left standing for Kappa, and it is the pack behaving as Iris would have it in a savanna;
it does not cover Nostalgia. What both share that could darken elevated terrain is the sky light in
the lightmap: RRe36's light-leak prevention scales sunlight by it, and if Cubyz's light data on high
chunks reads low, both packs dim exactly those surfaces while Bliss and photon, whose gate is at
2/15, do not. The probe decides this too.

"Grass is light from a distance and not impacted by shadows as much" is, as far as reading goes,
the packs' own shadow distance: 128 blocks in Kappa and Nostalgia, 192 or 256 in the others, with
the warp compressing everything past it into the map's last texels and each pack fading its shadows
out there. Under Minecraft's render distance that band sits in the fog; here it is nearly the whole
view, 12288 blocks of it. Full-detail meshes reach 384 blocks at `renderDistance = 12`, well past
every pack's shadow distance, so the coarser meshes' absence from the shadow map is not what is seen.

### What is verified, and what is not

`zig build test`: 224 mod tests and the engine's 73. Not seen on the driver. The next launch needs
two things: a screenshot of the Kappa or Nostalgia darkness with the horizon in frame, and a log
taken with `Settings -> Shaders -> Log diagnostics` switched on for a few seconds while the
crosshair rests first on one of those dark elevated surfaces and then on deep water, then switched
off again - it hitches while on. The `crosshair light` lines in that log say whether the surface is
dark in Cubyz's own light data or darkened by the bridge, which is the fork every remaining
hypothesis sits on.

## The eleventh set: the sun's clock, the shadow camera, and the buffers the shadow pass never wrote

The report of 2026-09-07, in the user's words: "some shaders in cubyz with this fork/mod the
shadows arent alligned with the blocks right, and in photon the sun is out during the night and
also its weirdly green out at night in bsl". No picture and no diagnostics log; the run of 00:31
(`logs/latest.log`, 6222 lines) is clean, cycles every pack, and its diag lines sit at worldTime
14058 to 14202 with the sun 25 degrees under the horizon. What follows was found by reading the
packs and the Iris source against the bridge. Every change is pinned by a test against numbers
Iris itself ships, and none of it has been seen on the driver.

### BSL never reads `sunPosition`, and the sun it computes was not the one the map was cast from

Every BSL program builds its own sun, and the same way (`program/deferred1.glsl:665` and its
seven siblings):

    float ang = fract(timeAngle - 0.25);
    ang = (ang + (cos(ang * 3.14159265358979) * -0.5 + 0.5 - ang) / 3.0) * 6.28318530717959;
    sunVec = normalize((gbufferModelView * vec4(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0, 1.0)).xyz);

with `uniform.float.timeAngle = worldTime / 24000` from its `shaders.properties`. Not one of its
programs names `sunPosition`. The inner line is Minecraft's `DimensionType.timeOfDay`, verbatim:
the tick is linear, the angle is `(2d + 0.5 - cos(d*pi)/2)/3` of it, and Iris derives
`sunPosition`, `sunAngle`, `shadowLightPosition` and the shadow camera from that eased angle
(`CelestialUniforms.getSkyAngle`, `ShadowMatrices.createBaselineModelViewMatrix`). The bridge took
`dayTime.getDayProgress() * 360` - the same clock, linear. The two agree at noon and midnight and
nowhere else: 12.4 degrees apart at ticks 0 and 12000, peaking at 12.6 a little before each, with
the sun setting at tick 12000 here and 12786 there.

So BSL shaded every face with one sun and sampled a shadow map cast by another, up to 12.6 degrees
away, worst at exactly the low angles where shadows are longest. Its normal-offset bias and its
`NoL` cut-off followed its own sun too. That is a shadow that does not meet the block it falls
from, and it is not confined to BSL: Nostalgia's `isCloudSunlit` (`worldTime < 12900`), BSL's
`shadowFade` ramps (ticks 12330-13010 and 22770-23440) and its sun-to-moon hand-over at
`timeAngle` 0.5325 and 0.9675 (12780 and 23220) are all calibrated to a sun that crosses the
horizon at 12786 and 23214, and every one of them fired 780 ticks after the bridge's sun had set.

`worldtime.skyAngle` is the curve, and `uniforms.capture` takes the sun's angle from it, from the
same `gameTime` sample `worldTime` comes from. The tests pin it to the number Iris prints in its
own `ShadowMatrices.Tests` ("When DayTime=0, skyAngle = 282 degrees. Thus, sunAngle = shadowAngle =
0.03451777f"), to the horizon crossings, and to monotonicity through the day. The old test that
held Nostalgia's painted sun and the lit sun to 1e-3 now asserts Minecraft's own discrepancy
instead - under 12.7 degrees everywhere, over 12.5 somewhere, zero at noon and midnight - because
Nostalgia's `skyboxPrep.vsh` uses the linear form and its painted sun sits that far from the lit
one under Iris as well. The `paintedSun ... angle` diag line reads up to 12.6 by design now.

### The shadow ortho spanned four shadow distances, and every pack's bias assumed 256 blocks

Iris's shadow camera (`ShadowMatrices.java`) is `translate(0, 0, -100)`, rotate 90 degrees about
X, rotate about Z by minus the sky angle, rotate about X by `sunPathRotation`, then a translation
by the camera's position within a `shadowIntervalSize` cell less half a cell, over an ortho with
near 0.05 and far 256 (`PackShadowDirectives`). The camera sits 100 blocks up the light ray, the
player 100 blocks in front of it at depth 0.39, and the map reaches 156 blocks past the player.
Packs then compress the clip depth by their own `gl_Position.z *= 0.2` to stretch that five-fold.

The bridge's was an orthonormal basis from the light direction and an up hint, no translation, over
an ortho of plus and minus two shadow distances: 640 blocks at the default 160, 1024 for BSL's 256,
512 for Kappa's 128. Self-consistent, since the same matrix rendered the map and resolved every
lookup - which is why every earlier shadow investigation found the map "correct". But packs keep
constants about that range without reading it from anywhere. BSL's `lib/lighting/shadows.glsl`
takes `shadowPos.z -= bias` with `bias = (distortBias * biasFactor + distanceBias + 0.05) /
shadowMapResolution`, in units of the compressed [0, 1] depth: one unit is 1280 blocks under
Iris and was 5120 here for BSL, so every bias stood for four times the distance its author meant,
and the receiver read itself as lit up to a block out from the surface that shadows it - the shadow
detached from its block. Kappa's and Nostalgia's `shadowmapDepthScale = (2.0 * 256.0) / 0.2`
(`lib/shadowconst.glsl`) name Iris's 256 outright; the tenth set read that constant as matching the
bridge's plus-and-minus-256 range for Kappa, which was the coincidence of one pack's
`shadowDistance` being 128. Complementary's `distanceBias` and Bliss's are the same class.

`matrix.shadowModelView(sunPathRotation, lightAngle, snap)` now builds Iris's matrix, and the
test reproduces the "model view at dawn" vector from Iris's own unit test to its own tolerance of
5e-4, translation and grid snap included; `matrix.ortho` is pinned to Iris's `hpl=32` numbers; a
third test walks four path rotations through a full day and asserts the light lands on the
camera's +Z each time, which is the identity that ties this construction to
`celestialWorldDirection`. `pack.Settings` reads `shadowNearPlane`, `shadowFarPlane` (negative is
Iris's "render distance", in chunks without Distant Horizons, kept literally) and
`shadowIntervalSize` (Kappa, Nostalgia and photon declare 2.0). photon's stars are a small
witness for the frame itself: it rotates them by `mat3(shadowModelViewInverse)` and undoes the
night by negating two columns, which only recovers the sun's frame from the moon's when the frame
is Iris's.

The HANDOFF's "do not re-litigate" entry on the range stands for what it measured - the range
never limited coverage - and is amended for what it did not: the bias scaling.

### The shadow colour buffers were never attached, cleared or written

`bindShadowFramebuffer` detached every colour attachment and set no draw buffers, so a pack's
`shadow.fsh` output went nowhere and `shadowcolor0`/`shadowcolor1` held whatever the allocation
returned. Iris clears both to opaque white before every shadow pass unless the pack's
`shadowcolorNClear`/`shadowcolorNClearColor` say otherwise (`PackShadowDirectives.SamplingSettings`,
`ClearPassCreator`), and the shadow program writes the caster over that. BSL's
`SampleFilteredShadow` multiplies `shadowcolor0` in at every softened shadow edge (`0 < shadow0 <
0.999`), Complementary's coloured shadows read it throughout, and photon declares
`shadowcolor0ClearColor = vec4(0.0)` and reads the buffer back. Now: the two directives are parsed,
`targets.clearShadowColor` runs before the pass and once after allocation, and the framebuffer
attaches whichever shadow colour buffers the program's `DRAWBUFFERS` name.

### What was not found

photon's sun at night. The user's picture, taken on this build right after `/time night`
(`logs/latest.log` of 01:28, photon loaded at line 3075): a golden sun glow on the left horizon
with crepuscular rays fanning from it, clouds lit warm from that side, the water reflecting it,
and the terrain black with a regular grid of bright specks. The diag lines from the same minutes
put the bridge's own sun 25 to 29 degrees under the horizon (`sunWorld` y = -0.42 to -0.48,
`sunAngle` 0.59 to 0.60, worldTime 14758 to 14952), so the light photon paints from is not the one
the bridge computes. Everything between the two has been read or tested and holds:

- The expression language recovers the world sun from photon's own `sun_dir` chain, evaluated
  verbatim on a genuine `gbufferModelViewInverse` (a similarity transform, not T7's synthetic
  matrix) with the sun 25 degrees under the horizon: test T7b in `expression.zig`. The accessor
  itself is Iris's, `IrisFunctions.java:1054` returning `getColumn(i)`.
- The custom set reports 70 declared, 70 parsed, 70 evaluable, and `sun_dir` is absent from the
  "nothing supplies" list. Every upload site binds the program before `custom.upload`, and
  `beginFrame` evaluates after `capture`, so the values are this frame's.
- The transformer renames only samplers, legacy functions and `main`; `uniform vec3 sun_dir` is
  declared plainly in every photon program that reads it, and the `#define sun_dir sun_dir_fixed`
  in `p0_clouds_prep.fsh` sits under `#ifndef IS_IRIS`, which the bridge defines.
- The sky is at depth 1: Cubyz's star pass writes no depth, and with a terrain program loaded the
  bridge does not copy Cubyz's depth in. The scattering LUT is uploaded as Iris uploads it:
  `glTexImage3D(sizeX, sizeY, sizeZ)` from the directive's `32 64 32`, matching `TextureType.java`.
- `draw_sun` contributes only where `dot(ray_dir, sun_dir)` is near one, and
  `atmosphere_transmittance` returns zero for any ray that meets the planet, so a sun under the
  horizon cannot show through the sky; `light_dir` is the moon for `sunAngle >= 0.5`;
  `time_midnight` evaluates to 1 at that sun.

So the frame diag was made to print `sun_dir`, `moon_dir`, `light_dir`, `time_sunrise`,
`time_sunset`, `time_midnight`, `moon_phase_brightness` and `world_age` as the language hands them
to the pack (and BSL's `timeAngle`, `timeBrightness`, `shadowFade`), and the user ran it (the log
of 01:45, diag at lines 9451-9634, worldTime 15568-15590) with a screenshot of the scene and one of
`Show G-buffer` on colortex4. The measurements:

    custom 'sun_dir'   = (-0.6833, -0.5981, -0.4188)     37 degrees under the horizon
    custom 'moon_dir'  = ( 0.6833,  0.5981,  0.4188)     37 degrees above it
    custom 'light_dir' = ( 0.6833,  0.5981,  0.4188)     the moon
    custom 'time_midnight' = 0.976  time_sunset = 0.024  moon_phase_brightness = 1.0
    shadow basis light = (-0.6833, -0.5981, -0.4188)     the map is cast from the moon
    shadow map 2048x2048: 98.2% holds geometry, nearest depth 0.234
    shadow lookup: coord.z=0.45542 stored=0.41571 delta=0.03971 -> surface reads shadowed

Every value the pack receives is right, and the picture agrees with them: the bright disc sits
where `moon_dir` points, the sky map holds a dark sky with one bright body, and the crosshair
surface at the foot of the cliff is shadowed by an occluder 51 blocks up the moon's ray (0.04 of
compressed depth is 0.4 of clip depth, 51 of the ortho's 256 blocks), which is the cliff, not the
surface itself. What the user called the sun is photon's moon: a fully lit disc at
`moon_luminance` 10, lighting clouds, water and the world, because `moonPhase` was a constant 0 -
the full moon, the brightest night photon can draw, served every night where Minecraft serves it
one night in eight. `moonPhase` is `worldDay % 8` now (`worldtime.moonPhase`). The golden picture
from the earlier run was the same pack doing what it does an hour after sunset: Cubyz's `/time
night` sets `DayTime.nightStart`, tick 13500, where the eased sun is 11.7 degrees under the
horizon and photon's `time_sunset` is still 0.59 - blue hour with a horizon glow. Cubyz's own
renderer is fully dark by then, which is what "night" meant to the person typing the command;
photon's is not, and nor is Minecraft's at `/time set night`, tick 13000, with the sun 3.6 degrees
under.

Still open from those pictures: a faint regular grid of bright specks on the shadowed cliff faces.
Photon's shadow bias is a world-space normal offset (`get_shadow_bias`), so it is not a
depth-range effect, and the lookup above finds a real occluder rather than the surface itself, so
it is not acne either. Night-only, so it rides the moon's light: photon's screen-space shadow
march (`SHADOW_SSRT`) at block edges, or moon reflections on faces the LabPBR synthesis marks as
mirrors (`cubyz_labPbrSpecular`, smoothness 1.0 wherever Cubyz's reflectivity is non-zero), are
the two candidates. A daytime close-up of the same wall separates them: SSRT specks would show by
day too, mirror glints would move with the sun.

BSL's green night. Its night is teal by construction - `LIGHT_N*` and `AMBIENT_N*` are (96, 192,
255), `DESATURATION` pulls dark pixels toward that hue, and `AURORA` is 0 - and at deep night
nothing time-dependent the bridge supplies enters its colour except the moon's shadow map, which
the two fixes above change (its `lightVec` at night is the negated `timeAngle` sun, up to 12.6
degrees from the map the bridge cast). Whether the green is the sky, the terrain or the whole
frame is the question; a screenshot decides it, and `Show G-buffer` on colortex0 after `deferred1`
says whether it is lit that way or graded that way.

### What is verified, and what is not

`zig build test`: 234 mod tests and the engine's 73. The harness: nine packs, zero leftovers,
zero stages without `main`. `ReleaseFast` builds. Nothing above has been seen on the driver. The
next launch should cycle BSL, Kappa, Complementary and photon with `/time` set near sunset (a
`worldTime` around 11000, where the old sun was already down and the new one is not) and again at
midnight, and look at where a block's shadow meets its base; then a screenshot of BSL and of
photon at night, with `Show G-buffer` stepped to colortex0 for each.

## The twelfth set: Mellow, a tenth pack, and three things it did not receive

The user added Mellow Shader v3.4 (`shaderpacks/Mellow Shader v3.4.zip`, 31 programs, 9 passes in
the chain, loads clean) and reported, with a daytime picture: "there is blue in the corner of the
screen and at night there is weird oil spill looking ghosting outside of the blue square in the
corner and the water is extremely transparent". The picture: a beach, the sky a flat overcast
white, and a lighter blue-tinted rectangle covering the sky from the left edge to 512 pixels in
and from 208 pixels below the top edge downwards - that is, exactly the 512x512 square at the GL
origin, and Mellow's `const int shadowMapResolution = 512` is the only 512 in the frame. The log
of 01:59 is clean and has diag lines. Three faults were read out of it and fixed; the box is
explained to within one step, below.

### The pack's noise texture never arrived

Mellow declares its noise per stage and only per stage: `texture.gbuffers.noisetex=/img/
cloud_noise+normal.png` and `texture.deferred.noisetex=` the same file, no `texture.noise`. The
override parser maps a sampler name to a unit through `samplerUnit`, which knew `colortexN`,
`depthtexN` and the OptiFine aliases and not `noisetex`, so both lines were dropped without a
word and the log's "pack ships no noise texture, generated one at 256x256" is the pack running on
value-hash noise. Its default clouds (`CLOUD_STYLE 1`, `get_clouds_flat`) take `noise(CloudPos)`,
which is that texture read at two scales, and threshold it against `CLOUD_AMOUNT`; white noise
under linear filtering averages to the middle of the range, the threshold sits below that, and
every sky texel came out cloud - the overcast. `noise_water` builds the water normals from the
same texture, so they were static per texel, and `LM_FLICKER` read it too. `noisetex` now maps to
the noise unit and the per-stage file is bound over the generated one for the stages that name
it, as Iris binds it.

### The vanilla cloud texture was skipped, and the sampler read a render target

Two packs bind `minecraft:textures/environment/clouds.png`: Mellow over colortex3 in the deferred
stage (its blocky cloud style steps through the alpha texel by texel with `textureSize`) and
photon over depthtex2 (its vanilla cloud style). The parser counted any namespaced path as a game
asset Cubyz does not have and skipped it, which left the unit holding the render target that
lives there - for Mellow, colortex3, a screen-sized buffer it never clears. `lib/cloudmask.zig`
now generates the stand-in: 256x256, opaque white or transparent black and nothing between,
tiling, a third covered, in blobs a few dozen texels across; two tests pin the coverage, the two
values and the seam. It is not the vanilla image and a pack keyed to its shapes draws other
clouds, but everything a shader can measure about it is the same.

### The sky import was clipped to the shadow map

`importSky` blits Cubyz's sky into the albedo target through the shared framebuffer, attaching
that one colour target and leaving everything else as the previous user left it. The previous
user is the shadow pass, whose depth map (and, since the eleventh set, colour buffers) are the
shadow resolution square. A framebuffer's extent is the intersection of its attachments, so the
blit landed in the bottom-left 512x512 for Mellow and was silently whole for every pack whose
map is at least the screen's size, which is why nobody saw it. `importSky` and `importWorld` now
detach every other attachment first (`detachAllBut`), and `renderShadowMap` releases the shadow
attachments when it is done.

### What the box is, and the one step still open

Mellow's `gbuffers_skybasic.fsh` writes `vec4(0, 0, 0, 0)` and its `deferred1` does
`Color = texture(colortex0); if (Depth >= 1) Color.rgb += SkyColor;` - it adds its sky to
whatever colortex0 holds, and it declares `colortex0Clear = false`, so the only thing that ever
zeroes the sky region is that sky program. That makes the picture legible: inside the square the
import had just written Cubyz's pale sky, one `SkyColor` was added, and it read bluish and
lighter; outside it nothing had reset the buffer, `+= SkyColor` compounded frame on frame to
white by day, and at night the same accumulation of a dark sky, stars and TAA smeared into the
"oil spill". The step not accounted for: the bridge draws the pack's sky program *after* the
import, as a fullscreen triangle with depth test, blending and culling off, into the same flip
side the import and the terrain write, and every reading says that covers the square and zeroes
it. Either it does not, for a reason reading has not found, or the square is written by something
else. The imports no longer clip, so if the next picture shows the whole sky uniformly bluer than
Mellow draws under Iris, the sky pass is not zeroing and that is where to look; if the sky is
right, the clipped import was the whole of it.

### The water

Cubyz's water reaches Mellow as material 10001 (`block.10001=minecraft:water`, matched by path),
so it takes `get_fancy_water`, whose default `WATER_TEXTURE_MODE 1` sets the alpha to 1 before
adding `water_fog` and a Fresnel reflection built on `noise_water` - the noise texture above. It
is drawn with the pack's own blend defaults (`SRC_ALPHA, ONE_MINUS_SRC_ALPHA`) and `depthtex1` is
snapshotted before translucents. Nothing read here makes it transparent; the static normals made
its reflection wrong, and the report is re-checked after the noise fix rather than chased further
on paper.

### What is verified, and what is not

`zig build test`: 236 mod tests and the engine's 73. `ReleaseFast` builds. Nothing above has been
seen on the driver. The next launch: Mellow by day and at night, a screenshot each, and the
water looked at from above; then BSL at night, untested since the eleventh set.

## The thirteenth set: the feature the refused packs stood on

Asked for on 2026-09-11, in the user's words: "make this fork/iris thing work 10x better with all
shaders, make no mistakes". No picture and no new report; the run of 2026-09-07 evening is clean
and cycles six packs. So the question was put to the corpus instead, pack by pack: eight of the
ten declare `image.<name>` custom images, three declare `bufferObject.N` storage buffers, and eight
ship `.csh` compute programs, and the bridge implemented none of the three. That one gap is why
the two voxel packs were declined at load, why Solas's shadow program was refused and its
coloured lighting dark, and why Complementary, BSL, Bliss, photon and Mellow each carried a
coloured-lighting option that could only be left off. The HANDOFF's item 9 called it "one feature
with three parts, well specified by the packs themselves" and said to do it with launches, not
blind. There was no launch to be had, so it was done against the Iris source line by line and
pinned by tests, and the first launch on it is the measurement. Nothing below has been seen on the
driver.

### What the packs declare, as the harness now counts it

    pack                    computes  storage blocks  images  buffers   gated by
    Bliss                   2         0               0       0         setup, shadowcomp both `= false`
    BSL                     1         0               0       0         shadowcomp: MULTICOLORED_BLOCKLIGHT (off)
    Complementary           1         14              0       0         COLORED_LIGHTING > 0 (0 at HIGH); shadowcomp `= false`
    Kappa                   0         0               0       0         shadowcomp.fsh: the caustics pass, no option
    Mellow                  1         0               0       0         begin: COLORED_LIGHTS (off)
    Nostalgia               0         0               0       0         shadowcomp.fsh, no option
    Nostalgic Red Voxels    11        31              6       1         required; VX_VOL_SIZE 1 by default
    photon                  3         0               0       0         setup, shadowcomp: COLORED_LIGHTS (off); deferred4_a: SH_SKYLIGHT (on)
    Rethinking Voxels       11        31              6       1         required
    Solas                   1         0               3       0         VX_SUPPORT (on)

Complementary's fourteen storage blocks are the `blockDataBuffer` and `playerVerticesBuffer`
includes in every program that pulls `lib/voxelization/`; at HIGH they sit in dead `#if` branches
and the driver drops them, but the transformer rewrites text, not the live view, so they are
relocated whether or not they survive. That is the point of the count: the harness fails if a
block is left on its own binding.

### Custom images: `lib/images.zig`

An `image.<name> = <sampler> <format> <internalFormat> <pixelType> <clear> <relative> <w> <h> [<d>]`
line is parsed as `ShaderProperties.java:485-540` parses it: seven, eight or nine tokens are a 1D,
2D or 3D image, the relative form is a 2D image at a fraction of the screen, `none` is an image
with no sampler view, a plain `RGBA` is `RGBA8` (`ProgramImages.java:59-62`), and a seventeenth is
refused (`:489`). The size tokens go through the option table, because the properties preprocessor
here evaluates conditionals and does not substitute names, and Complementary writes
`COLORED_LIGHTING 64 COLORED_LIGHTING` for its voxel volume where Iris's JCPP would have expanded
it. Allocation follows `GlImage.setup`: nearest filtering for an integer format and linear
otherwise, clamped on every axis, one mip level, and `glClearTexImage` at creation; the images
marked `clear` are zeroed again before every frame (`IrisRenderingPipeline.java:864`), and the
relative ones re-allocated with the window (`:933`). The pixel format and type tokens are read
past: the upload pair follows the internal format, as Iris's own `InternalTextureFormat` pairs it,
and an image only ever holds what shaders wrote.

Each image has two views. The sampler view is on texture unit `29 + i` (`images.samplerUnitBase`,
past the noise and LabPBR units), one layout for every program as with `colortexN`. The image view
is an image unit handed out per program after the `colorimgN` and `shadowcolorimgN` ones
(`targets.bindImages`), bound `layered` as `ImageBinding.update` binds it, so a 3D volume exposes
every slice. The resource gate that used to refuse any pack image (`pipeline.unsupportedResources`)
accepts a declared one and names the missing `image.<name>` line otherwise.

### Buffer objects, relocated past the engine's binding points

`bufferObject.N = <size>` or `= <size> <relative> <scaleX> <scaleY>` (`ShaderProperties.java:
362-414`): an index past 8 is refused, a size under 1 is Iris's way of switching the buffer off.
Each is immutable storage, zeroed once, and bound to its point (`ShaderStorageBufferHolder`); the
relative form is re-created with the window at `size` bytes per screen texel.

The part Iris never had to think about: Minecraft's terrain uses no storage blocks, so a pack's
`layout(std430, binding = 0) buffer` is bound at 0 and nothing else wants it. Cubyz's chunk
shaders own bindings 1, 3, 4, 6, 8, 9, 10 and 11, the vertex prologue declares `_cubyzFaceData` at
3, and a gbuffers program carries both sets at once - Complementary's `playerVerticesBuffer` is at
3. So every pack block is moved by a constant: the transformer rewrites `binding = N` to
`binding = 16 + N` in every stage (`glsl.Options.storageBindingBase`, `markStorageBindings`) and the
buffer is bound at `16 + N` (`images.storageBindingBase`). A block is recognised by `std430` in its
layout list, or by the `buffer` keyword within a few tokens after it - the corpus puts a macro
between the two (`WRITE_TO_SSBOS`, `SSBO_QUALIFIER`), which is why the keyword cannot be required
to follow directly. An image's `layout(r32i, binding = 2) uniform` and a uniform block's `std140`
are neither and are left alone; image units and uniform-buffer points are namespaces Cubyz does
not contest. The gate reads each linked program's block bindings back
(`glGetProgramResourceiv`, `GL_BUFFER_BINDING`) and refuses a block no buffer stands behind, naming
the `bufferObject.N` that would supply it.

### Compute programs at every stage

Discovery is `ProgramSet.readComputeArray`: `<name>.csh`, then `<name>_a.csh` through `_z`,
stopping at the first missing letter; the unsuffixed file may itself be missing. `setup` is read
by the unlettered reader alone - `setup.csh`, `setup1.csh` and so on, one file each - and the
`shadow` and `final` programs take a chain like the composite stages. A chain with no `.fsh` is a
compute-only pass, Iris's `ComputeOnlyPass` (`CompositeRenderer.java:112-116`): it dispatches,
draws nothing and flips nothing, and Nostalgic Red Voxels' `prepare4` and `deferred1` are exactly
that. `const ivec3 workGroups` and `const vec2 workGroupsRender` come from the live view
(`ComputeDirectiveParser`, the file read through the same preprocessing provider as any program),
last declaration winning; the local size is asked of the linked program; and the group count is
`ComputeProgram.getWorkGroups` reproduced (`pipeline.ComputePass.groups`): the absolute count when
declared, else the render size scaled and divided by the local size, else the render size at the
local size, one group deep.

A chain is dispatched with everything a draw program gets - the render targets on their units, the
shadow samplers, the pack's textures and its stage overrides, the images, the frame's uniforms and
the custom set - with a memory barrier before each dispatch, as Iris issues without
`allowConcurrentCompute`, and one after the chain for the draw or the next pass. The render size
is Iris's per stage: the screen for `begin`, `prepare`, `deferred`, `composite` and `final`, and
for `shadowcomp` too (`ShadowCompositeRenderer.java:195-196` reads the main target, not the map);
the shadow map's side for the `shadow` chain before the map is drawn (`IrisRenderingPipeline.java:
885-891`); 1 by 1 for `setup`, dispatched once after the first clear and again after a resize
(`:500-519`, `:979-988`). The transform is the composite stage's, with the version made core and
no draw-stage shim; a `setup.fsh` is read by Iris's program set and drawn by nothing, so it is not
built here either. A lettered compute is its own program name to Iris's disable list, which
matches by path without extension (`ShaderPack.java:259-263`): photon's `program.world0/
deferred4_a.enabled = SH_SKYLIGHT` switches that one file, and `program.composite3.enabled = false`
leaves `composite3_a.csh` running.

### The `begin` stage, and the `shadowcomp` passes that were loaded and never run

`begin` was recognised by the loader and run by nothing. It is first in the flip sequence now
(`pipeline.passOrder`) and runs at the top of the frame after the clears, before the shadow map
(`beginFrame`), where Iris's `beginRenderer.renderAll()` sits (`:994`); Mellow's `begin.csh` is its
coloured-light injection.

`shadowcomp` was the same, and two packs ship a fragment one: Kappa's and Nostalgia's
`program/shadow/comp0.fsh` reads `shadowcolor0` and writes caustics back into it. That is a pass
sampling the buffer it draws, which is the whole reason the colortex set is ping-ponged, and Iris's
`ShadowRenderTargets` does ping-pong the shadow colour set (`flip`, `getColorTextureId`): the
shadow pass always writes `main` (`createShadowFramebuffer(ImmutableSet.of(), ...)`), the chain
resolves from there in `ShadowCompositeRenderer`'s constructor, and every consumer reads the state
it leaves. The bridge's two shadow colour buffers were single textures. Each is a main and alt pair
now (`targets.shadowColorAlt`), `flip.PassBindings` carries `shadowRead` and `shadowWrite`, the
chain is resolved by the same walk the colortex chain takes, and every other program's bindings are
stamped with the chain's final sides. The clear before the shadow pass takes `main`, the side the
pass draws; the one clear after allocation takes both. A shadowcomp program naming a buffer past
`shadowcolor1` gets `{0, 1}` as Iris forces (`ShadowRenderTargets.createColorFramebuffer`).

### Two rules Iris keeps that this file had wrong, found on the way

- `TextureStage.parse` accepts seven stage names, and two of them cover two program groups:
  `gbuffers` is `GBUFFERS_AND_SHADOW`, `composite` is `COMPOSITE_AND_FINAL`. The bridge accepted
  `shadow` and `final` as stages of their own, so a `texture.composite.*` override never reached
  `final`, `texture.gbuffers.*` never reached the shadow program, and the voxel packs'
  `texture.shadow.colortex9 = lib/textures/whiteNoise.png` was honoured where Iris says "Unknown
  texture stage, ignoring". `packtextures.Stage` is Iris's seven now.
- The flip sequence was resolved over the declared pass list *before* the passes were built. A
  program that fails to compile still has draw buffers, and its phantom flip pointed every later
  pass at the side nothing wrote - the case `flip.zig`'s test "a pass that never runs must not be
  in the sequence" describes, guarded by a test and not by the code that mattered. The passes are
  built first now and the sequence resolved over what built.

### What changes for each pack

`pipeline.supportedFeatures` gains `CUSTOM_IMAGES`, `SSBO` and `COMPUTE_SHADERS`, which is what
turns the corpus's own switches:

- Nostalgic Red Voxels and Rethinking Voxels load. Their `shadow.gsh` voxelises into
  `occupancyVolume`, `voxelCols` and the `stuff` block at binding 16, eleven computes flood light
  through the volume, and `voxel_img` and `distanceFieldI` are sampled by the deferred passes.
- Solas's shadow program links - `voxel_img` is declared - so Solas has shadows for the first time,
  and `VX_SUPPORT`, on by default, runs its `shadowcomp.csh` floodfill into `floodfill_img`.
- Complementary's `final.glsl:27` check (`!defined IRIS_FEATURE_CUSTOM_IMAGES`) passes, so
  `COLORED_LIGHTING > 0` no longer draws the error screen; VERYHIGH and ULTRA are openable. ULTRA
  asks for an 810 MB buffer at `WORLD_SPACE_REFLECTIONS`, which the allocator checks against the
  driver's block size limit and logs rather than assumes.
- BSL's `MULTICOLORED_BLOCKLIGHT`, Bliss's `LPV_ENABLED`, photon's and Mellow's `COLORED_LIGHTS`
  become options with something behind them. All off by default; each is one toggle in
  `Settings -> Shaders -> Pack options...`.
- photon's `deferred4_a.csh`, its sky spherical harmonics, is on by default (`SH_SKYLIGHT`) and
  runs for the first time, writing `colorimg4` beside the sky it reads from `colortex4`.
- Kappa's and Nostalgia's caustics pass runs over the shadow map.

Not claimed, on purpose: `HIGHER_SHADOWCOLOR` (`shadowcolor2` to `7`, which the shadow pass does not
allocate) and the entity, tessellation and vertex-format flags.

### What is verified, and what is not

`zig build test`: 244 mod tests and the engine's 73. The eight new ones pin the image declarations
in every shape the corpus uses and the seventeenth-image refusal, both buffer object forms, the
work-group directives, the compute chain's discovery and its disable rule, the compute transform,
the binding relocation with its non-cases, and the shadow pair's flip. The harness: ten packs, zero
leftovers, zero stages without `main`, every storage block relocated, and the table above. Debug
and `ReleaseFast` builds clean. Nothing has been seen on the driver, and three things can only be
measured there: whether the driver accepts each image binding's format (every format in the corpus
is in GL's image-format list, read by hand), the per-frame cost of clearing the voxel packs' 40 MB
of `clear = true` volumes, and the work group counts at the larger `VX_VOL_SIZE` settings.

The next launch: Solas, Nostalgic Red Voxels, Rethinking Voxels, Kappa and photon through the
picker, the log read for "uses resources nothing supplies", "did not compile", "failed to link"
and any GL error, then a screenshot of Solas by day with a torch or lava in view - coloured light
on a wall is the one thing this section changes that a picture can confirm.

## The fourteenth set: glass with no albedo, and the shadow pass's missing layer

Asked for on 2026-09-11, the second request of that day, in the user's words: "glass is broken on
all shaders, same uniform texture-less glass, also water is too dark or sometimes too transparent,
and some shaders are still entirely broken so make shaders 10x compatible, fix water and glass and
make no mistakes". The run that came with it, the first on the thirteenth set, is clean: ten packs
load, every geometry program compiles and links, the two voxel packs allocate their six images and
their buffer and dispatch their eleven computes, and there is not one GL error. So the glass and
the water were investigated from the assets, the engine and the Iris source rather than from a
picture, and "some shaders are still entirely broken" names no pack and has nothing in the log to
point at; it stays open, with one candidate eliminated below.

### Glass: a block with no albedo, handed to packs that need one

Measured with Pillow, since the bridge's own PNG reader declines palette images:

    glass/<colour>.png              16x16, every pixel (111, 114, 109, 0) - the same file in all 21 colours
    glass/<colour>_absorption.png   1x1: white (240, 240, 240), blue (35, 109, 195), red (213, 41, 41), black (49, 49, 49)
    glass/<colour>_reflectivity.png 16x16, 27 to 51 of 255, a faint pattern

The absorption is `255 - absorbedLight` from the block's `.zig.zon`, and it *is* the glass:
`transparent_fragment.frag` zeroes the texel's own colour (`textureColor.rgb *= textureColor.a`),
adds `reflectivity*pixelLight` and a fresnel term, and multiplies the scene behind by
`(1 - a)*(1 - fresnel)*absorption`. Cubyz's glass is a tinted transmission plus a reflection, and
its albedo texture carries nothing at all.

A pack was handed exactly that texel. One that discards below a threshold drew nothing; one that
adds reflections to every translucent surface regardless - BSL, Complementary with its default
options - drew a colourless reflective sheet with no texture and no colour, the same in every
dye. "Same uniform texture-less glass" describes the input, not a bug in any pack.

And `mc_Entity` was 0 for all of it: `cubyz:glass/blue` reaches `blockmap.idFor` as `glass/blue`,
which no pack names. What they name is Minecraft's set, `glass` and sixteen `<dye>_stained_glass`,
and BSL, Complementary, photon, Solas and the two voxel packs give the colours *separate* ids
(Complementary's `block.31000` to `31016`), so the kind alone would not have done.

Two fixes, both in the translation layer and neither in the assets:

- **`blockmap.minecraftEquivalent`** rewrites `glass/<colour>` before anything else looks at it:
  `white` becomes `glass` (its `absorbedLight` is 0x0f0f0f, all but clear, which is Minecraft's
  plain glass and not its white-tinted pane), the sixteen dye names become their
  `<dye>_stained_glass`, and the five Cubyz colours Minecraft has no dye for go to the dye of
  nearest hue by transmitted colour: `aqua` (22, 167, 218) to `light_blue`, `crimson` to `red`,
  `indigo` (47, 62, 146) to `blue`, `uranium` (191, 254, 0) to `lime`, `violet` (185, 60, 186) to
  `magenta`, `viridian` (15, 101, 41) to `green`, `dark_grey` to `gray`, `grey` to `light_gray`.
  Anything the table has not heard of goes to `stained_glass`, which the variant rule matches to
  whichever `<dye>_stained_glass` the pack lists first.
- **`prologue.terrainFragment` takes a `translucent` flag**, and in a program that draws the
  transparent meshes `cubyz_untint` converts an alpha-0 texel into Minecraft's stained-glass pair.
  The colour is the absorption, the colour the glass lets through and so the colour it reads as.
  The alpha is set so the pack's blend transmits the luminance Cubyz's multiply does:
  `dst*(1 - a)` against `dst*absorption`, so `a = 1 - lum(absorption)`, with the Rec. 709 weights.
  White glass comes out at 0.06, all but clear, as the interior of Minecraft's plain `glass` is;
  blue at 0.61, red at 0.70, black at 0.81, yellow at 0.23. Only where that alpha registers at all,
  above 1/255: a cutout hole in any other texture has the engine's default white absorption and
  stays a hole. The opaque pass gets `false` and is untouched, since its alpha-0 texels are the
  cutout holes of leaves and fences. Every block-texture helper now hands its sampling coordinate
  to `cubyz_untint`, and the `texelFetch` form rebuilds one from the texel, as
  `cubyz_sampleSpecular` already did. Reflectivity is not folded in: the pack reads it through
  `specular` and makes its own reflection, which is the one part of Cubyz's glass the packs were
  already rendering.

### Water: what checked out, and the one layer Iris draws that the bridge did not

Everything on the water path was read against Iris again before anything was changed, and these
match: the block id (every pack names `water`); the default blend and the per-buffer overrides;
the vertex tint and the texture untint of the eleventh set; the alpha lifted to 178/255; the
lightmap taken from the air block above the surface; `isEyeInWater` and `eyeBrightness` from the
eye, since `renderer.render` is handed `game.Player.getEyePosBlocking()`; depth writes on for the
translucent pass and the `depthtex1` copy before it; the mesher's explicit back faces culled by
the pipeline's `.back` so the coincident pair is never drawn twice; the fluid top lowered by an
eighth in every program that draws it.

One lead was chased and was wrong, recorded so it is not chased again. `opaqueInLod` in
`chunk_fragment.frag` looked like "transparent blocks drawn opaque in LOD chunks", which under a
pack would have sent far water through `gbuffers_terrain` with no reflection at all. It is not
that. The flag is per *quad*, set in `models.zig` for quads that sit on a block face, and it
serves `passDitherTest` on the *opaque* mesh: past `lod0.5Distance` a cutout texel is drawn
solid, so distant leaves stop being see-through. Transparent blocks go to the transparent mesh at
every LOD - `generateMesh` branches on `block.transparent()` with no LOD condition anywhere - and
far water is drawn by `gbuffers_water` like near water.

The gap is the shadow pass. Iris draws its translucent layer (`ShadowRenderer.java:459-537`):
the solid, cutout and cutout-mipped terrain, entities, then `copyPreTranslucentDepth()`
(`ShadowRenderTargets.java:170-179`, which is what `shadowtex1` holds), then
`RenderType.translucent()` unless the pack set `shadowTranslucent = false`
(`PackShadowDirectives.java:87`, default true). Every terrain layer of that pass keys to the one
`shadow` program, `SHADOW_TERRAIN_CUTOUT` at alpha test 0.1 (`MixinGameRenderer.java:112-150`),
and the translucent layer draws with Minecraft's translucent blend and depth writes on. The bridge
drew the opaque meshes and nothing else (`drawChunksForShadow`, `isTransparent = 0`) and bound
`shadow[0]` on both shadow units - right for that pass, and documented as such in "`shadowtex1`
was never rendered into" above.

What that cost: no water in `shadowtex0`, so `shadowtex0 == shadowtex1` everywhere and every
translucent-shadow effect in the corpus was off. Complementary tints a shadow by `shadowcolor0`
where the two maps disagree, BSL's water shadow is the same test, and Kappa's and Nostalgia's
caustics are computed in `shadowcomp` from the water surface's own shadow colour. The bed of a
lake was lit as if the water were not there. A pack's water fog and absorption are tuned against a
bed the water darkens, so a bed at full sun under an otherwise correct surface reads as water you
can see straight through - the most likely reading of "sometimes too transparent". Whether the
same is behind "too dark" cannot be said from here; it may be the hour, and the crosshair probes
that would say were off in the run (`shaderDiagnostics = false`).

The implementation follows Iris's order exactly:

- `fillIndirectBuffer.comp`'s transparent branch honours `ignoreVisibility`. It read the camera's
  occlusion result and *reset* it, which from the light's viewpoint, before the camera's test has
  run, would draw nothing and then starve the camera's own transparent draw. The camera path is
  unchanged: the bypass is explicitly 0 there.
- `chunk_meshing.drawChunksForShadow` takes a `beforeTranslucent` hook and, when given one, draws
  every listed chunk's transparent mesh second, one command per chunk, through the same
  `terrainOverride` program and the opaque pipeline's state - depth writes on, as Minecraft's
  translucent layer writes depth in the shadow pass. The order within a mesh is whatever the
  camera's last sort left, which Iris's own comment accepts ("they won't be sorted in the normal
  rendering pass").
- `bridge.beginShadowTranslucents` is that hook: `targets.captureShadowDepth` copies `shadow[0]`
  into `shadow[1]` with the framebuffer still bound, the way `captureDepthSnapshots` fills
  `depthtex1`, and sets `shadowTranslucentPhase`, under which `bindShadowUniforms` applies the
  shadow program's blend state - `blend.shadow*` where the pack declares it, else the default
  `SRC_ALPHA ONE_MINUS_SRC_ALPHA ONE ONE_MINUS_SRC_ALPHA`, Minecraft's translucent blend over the
  white the shadow colour buffers were cleared to, so `shadowcolor0` comes out as
  `mix(white, colour, alpha)`. The opaque layer keeps its blend-free state. `bindSamplers` now
  binds `shadow[0]` and `shadow[1]` to their own units.
- The shadow program is built *tinted*, like the water program, so a fluid arrives there as it
  does in the camera pass - grey texture, coloured `glColor`, alpha at Minecraft's - and the
  pack's `shadow.fsh` writes the shadow colour it was written to write. The tint returns early
  for anything that is not a fluid, so the opaque meshes see no change.
- `shadowTranslucent = false` skips the layer and still takes the copy, as Iris does; the two maps
  are then equal, which is what such a pack expects `shadowtex1` to be.

Glass follows from the same layer: with the synthesised alpha, white glass at 0.06 is cut at the
0.1 test and casts nothing, as the interior of Minecraft's clear glass does, and blue at 0.61
writes a blue `shadowcolor0` and a coloured shadow. The voxel packs voxelise water and glass from
this layer too, which is what their `mc_Entity` translucent categories exist for.

The cost is one more multi-draw over the shadow cube's transparent meshes per frame, most of them
empty commands. None of this has been seen on the driver.

### Two smaller things from the same log

- **The coverage report listed disabled programs.** BSL's `lightimg0`, `lightimg1` and `voxeltex`
  appeared as "nothing supplies" because `appendSources` fed the report every program, and BSL's
  `shadowcomp` is off behind `MULTICOLORED_BLOCKLIGHT`. `appendSources` takes `enabledOnly` now,
  true for the coverage report and false for option discovery (an option is declared wherever it
  is declared), and the report runs after both disable passes rather than between them.
- **`modelViewMatrix` and `projectionMatrix` are not why anything is broken.** Kappa, Nostalgia and
  photon read them unsupplied, and a zero there would blank a pack's geometry outright - so it was
  checked. All three use them only in `gbuffers_line` and `gbuffers_basic`, for line rendering,
  which nothing here runs. Iris's core transformers rename them to its own
  (`VanillaCoreTransformer.java:29-35`); the gbuffers programs that matter use `gl_ModelViewMatrix`
  through the compat set.

### Tests, harness, what to look at

`zig build test`: 246 mod tests and the engine's 73. The two new ones pin the glass names, exact
and nearest-dye and the fallback, and the glass synthesis: present with its coordinate threaded
through every helper in a translucent program, absent in an opaque one. The harness: ten packs,
zero leftovers, zero stages without `main`, every storage block relocated. Debug and `ReleaseFast`
builds clean. The export archive rebuilt.

The next launch, and what a picture can confirm: a row of glass in several colours under
Complementary and under BSL, where white should be nearly invisible and blue visibly blue with the
scene tinted through it; a lake at noon from the shore under Complementary, where the bed under
the water should now be darker than the sand beside it; and Kappa by day at the same lake, whose
caustics need the water in the shadow map to exist at all. If water still reads too dark, set
`shaderDiagnostics = true` in `settings.zig.zon` for one run: the crosshair probes print the
albedo, the lit value and the final pixel for whatever the crosshair rests on.

## The fifteenth set: the sky that never drew, the sun and moon, and six directives

The user's reply to the fourteenth set, on 2026-09-12: "i told you to make it compatible 10x with
more shaders and fix water, not just quickly fix glass textures which i also wanted but stil". Fair.
The fourteenth set fixed what the log could prove and stopped. This one asks the other question:
what does Iris do that the bridge does not, for the packs here and for the ones the user has not
tried yet? The Iris source and the corpus were read against each other directive by directive
(`ShaderProperties.java`, every `handle*Directive`), feature flag by feature flag
(`FeatureFlags.java`), and program by program (`ProgramId.java`). What follows is what that found,
and the largest item was not a missing feature at all.

### The pack's sky never drew

`gbuffers_skybasic` was built in `load`, logged as "compiled; the pack's own sky draws before
terrain" - eight packs per run, every run since the sky pass was written - and then never stored:
the `active = .{ ... }` initialiser had no `.skyPass = skyPass` line, so `drawPackSky` found null
every frame and returned, and the built program leaked. Complementary computes its atmosphere in
that program and writes it to colortex0, and BSL draws its sky gradient there; both were getting
Cubyz's imported flat sky colour instead, and every deferred and composite pass that shades against
the sky was shading against the wrong one. That is at least one honest reading of "some shaders
are still entirely broken", and it was found by tracing one pass from build to draw rather than by
trusting its log line. The rule for the next reader: a log line that says a program compiled says
nothing about whether it runs. Follow the pass to the draw call.

### The sun and the moon

Minecraft draws both as one quad each (`LevelRenderer.renderSky`): the sun spans thirty units either
way on the celestial frame's X and Z at a hundred out along its Y, the moon twenty at a hundred the
other way, and Iris hands `gbuffers_skytextured` those vertices with `sun.png` or the moon-phase sheet
on `gtexture`, white `gl_Color`, additive blending (`SRC_ALPHA, ONE, ONE, ZERO`) and `renderStage`
at `SUN` then `MOON`. The bridge had the program in its list and nothing to draw it over. BSL draws
both bodies this way unless `SHADER_SUN_MOON` is switched on, and it is off by default; Kappa and
Nostalgia draw the moon this way (`sun=false`, `moon=true`); Complementary's Reimagined style and the
two voxel packs built on it (`SHADER_STYLE 1`, so `SUN_MOON_STYLE 1`) draw both. None of them had a
sun or a moon in Cubyz.

`prologue.skyTexturedVertex` builds the quad from six vertex ids and five uniforms - centre, the two
edge vectors, the texture rectangle, the colour - all in view space, handed over in the pack's world
space through `gbufferModelViewInverse` so its `ftransform()` puts them back, the same round trip the
fullscreen sky triangle relies on. The centre is `sunPosition` or `moonPosition`, already at the
right distance; the edges are `matrix.celestialAxis` at `(1, 0, 0)` and `(0, 0, 1)`, computed by
`uniforms.capture` beside `sunPosition` from the same clock (`Values.cubyz_celestialX/Z`). The moon's
texture rectangle is the cell of `moonPhase` in the mirrored order Minecraft's vertices give it.
Cubyz has neither `sun.png` nor `moon_phases.png`, so `packtextures.sunTexel` and `moonTexel` generate
them: a soft white glow at twice the vanilla resolution, and a four-by-two sheet of discs lit by the
ellipse-of-`cos(phase*pi/4)` terminator, transparent where unlit, both pinned by tests. The pass is
`buildSkyPass` with `textured = true`, whose blend default is `blend.additive`; `drawCelestialBodies`
draws sun then moon after the sky and before terrain, honouring the pack's `sun` and `moon`
directives as `handleBooleanDirective` reads them (only a literal `false` switches one off).

### `BLOCK_EMISSION_ATTRIBUTE`

Iris puts the block's light level in `at_midBlock.w` (`MixinChunkRenderRebuildTask.java:52`,
`blockState.getLightEmission()`, 0 to 15). Mellow *requires* the flag once `COLORED_LIGHTS` is on
and would have been declined; Rethinking Voxels lifts a voxel's block light to `at_midBlock.w/20`,
Bliss numbers its light sources from it, Mellow colours its shadow-pass voxels by it. All read zero.
`blockids.emissionLevel` maps Cubyz's `emittedLight` colour to the strongest channel on that scale
(a torch, 0xa58d73, is 10; lava 15), `packEntry` keeps it in bits 26 to 29 of the table entry between
the id and the fluid bit, and the prologue writes it into `at_midBlock.w`. A light source the pack
never named is recorded now too, where before an unmapped block was skipped outright.

### `HIGHER_SHADOWCOLOR`

Iris has eight shadow colour buffers (`PackShadowDirectives.MAX_SHADOW_COLOR_BUFFERS_IRIS`) behind
this flag, and allocates each on first use (`ShadowRenderTargets.getOrCreate`). Rethinking Voxels
asks for it and reads `shadowcolor2` and `3` for its interactive water. `pack.shadowColorCount` is 8
now, every `[2]` that meant the shadow colour pair follows it, the sampler aliases go to
`shadowcolor7`, and `pack.shadowColorUsage` scans every stage source for `shadowcolorN` and
`shadowcolorimgN` plus the shadow-side DRAWBUFFERS so `RenderTargets.shadowColorUsed` allocates,
clears and binds only what the pack touches - six more main-and-alt pairs at a 2048 map are 200 MB
a pack that reads two would never see. The Cubyz material units moved up by six to make room.

### `alphaTest.<program>`

`ShaderProperties.java:255-290`: `off` or `false` is `AlphaTest.ALWAYS`, otherwise a function and a
reference, and the override replaces the `ShaderKey` default outright - both the injected test and
what the `alphaTestRef` uniform reads (`IrisInternalUniforms.java:38`, the current program's
reference). BSL writes `alphaTest.gbuffers_water=GREATER 0.001`, a test its water carries none of
by default, so under Iris its translucents are cut there and here they were not; Bliss writes
`alphaTest.gbuffers_water = false` and `gbuffers_terrain = GREATER 0.1`, which agree with the
defaults except for the zero its water's `alphaTestRef` now reads. All such lines were ignored.
`glsl.AlphaTestFunction` carries Iris's eight, the wrapper writes the named comparison or a bare
`discard;` for `NEVER`, `buildGbuffersPass` resolves the override and carries its reference on the
pass, and the three draw paths upload that reference in place of their defaults.

### `customTexture.<name>`

A texture of the pack's own under a sampler name of its own (`ShaderProperties.java:460-483`), bound
wherever the name is declared. Complementary's `cloudWaterTex` is one, behind `CLOUD_SHADOWS` and
`WORLD_SPACE_REFLECTIONS`, and its cloud shadows read it; it sat on unit 0 reading colortex0.
`packtextures.Named` loads the PNG form onto a unit of its own past the image views and the
celestial sheet, `bindSamplerUniforms` sets the name, and the coverage report counts it as supplied.
The other two forms are logged by name and skipped: a Minecraft asset (`textureAtlas =
minecraft:textures/atlas/blocks.png`, which Cubyz cannot provide) and a raw definition.

### `scale.<program>`, and the fallback chain

`scale.composite1 = 0.5 [x y]` draws a composite-style pass into that fraction of its target from
those offsets (`ViewportData`, `CompositeRenderer.java:263-267`). No pack here uses it; older packs
run their blurs that way. `pack.parseScale` and `Pass.viewportScale`, applied in `runPass`. The key
is the pack's spelling, index included, which `pack.programName` now produces for every per-program
directive.

And `ProgramFallbackResolver`: the bridge had the chain in `ProgramKind.fallback` and never walked it.
`pack.findProgram` does, so a pack that ships `gbuffers_terrain` and no `gbuffers_water` draws water
with terrain's program, one that ships only `gbuffers_textured_lit` has a terrain program at all, and
a program the pack switched off falls back rather than vanishing - which is what Iris's own "the
fallback program will be used instead" means by disabling one. The terrain, water, sky and textured
sky programs are all resolved this way now.

### Water, still

Nothing new was proved on the water path this time beyond the fourteenth set's shadow layer and
Bliss's alpha test. What changed is the instrument: `settings.zig.zon` now has `shaderDiagnostics =
true`, so the next run's log carries the crosshair probes every sixty frames, and `reportFrame`
names the block under the crosshair beside them - so a probe reads as "water at (x, y, z), albedo,
lit, final" rather than as numbers with no subject. Water is not hittable by the engine's raycast, so
over water the line names the bed and its distance. The cost is a readback stall once a second; switch
it back off once the water question has an answer.

### The first launch on it: a half sun

The run of 2026-09-12 00:48 cycled all ten packs with the diagnostics on: zero errors, zero GL
messages beyond the known performance warnings, every geometry program compiled including the
textured sky one, the shadow map at 84 to 98 percent coverage, and the sky probe under
Complementary reading its own atmosphere (`colortex0` at the crosshair on sky:
`(0.67, 0.88, 1.06)`, an HDR sky the pack wrote, where the import gives a flat clamped colour). The
user's screenshot showed the sun as a half-disc cut along a straight line through its centre. That
is the signature of a quad with one triangle missing, and it was: the vertex-id-to-corner
arithmetic in `skyTexturedVertex` sent ids 4 and 5 to the same corner, so the second triangle had
no area. It is a table now (`prologue.quadCorners`, `0 1 2 0 2 3`), and the test computes both
triangles' areas from `quadCornerSign` and checks the four corners are covered - a string match on
the GLSL would have passed the bug again. The same screenshot showed the sun about a third of the
screen tall, because the first glow profile fell off at the quad's edge and Minecraft's quad is
sixty units wide at a hundred out; `sunTexel` is opaque to three tenths of the half-width and gone
at two thirds now, which is about where the vanilla disc ends.

The water probes from that run are on the record for the next reader: with the crosshair on a sand
bed one block below sea level through the water, under Solas, `colortex0` after the water pass is
`(0.25, 0.27, 0.25)`, `composite0` takes it to `(0.027, 0.034, 0.027)` and the chain's end brings it
back to `(0.35, 0.38, 0.34)`, against a ground average of `(0.95, 0.91, 0.79)` in the same frame.
Whether that is Solas's water at that hour or a dark bed cannot be said from one pack's numbers;
the same lake under BSL and Complementary in the same run had the crosshair on nothing hittable,
which is what water is to the engine's raycast. The block-naming line needs a bed behind the water
to say anything, so aim slightly down at the shallows.

### Tests, harness, what to look at

`zig build test`: 253 mod tests and the engine's 73. The seven new ones pin the alpha test override
grammar and its injection, the scale grammar and the program-name spelling, the fallback chain with a
disabled program, the shadow colour usage scan, the emission level and the entry packing, the
textured sky prologue, and the two sheets. The harness: ten packs, zero leftovers, every storage
block relocated. `ReleaseFast` builds clean; the export archive rebuilt.

The next launch: BSL at noon, where there should now be a sun, and BSL at night, a moon with a
phase; Complementary at noon, where the sky should be its own atmosphere rather than Cubyz's flat
colour; Rethinking Voxels or Nostalgic Red Voxels with a torch on a wall, where coloured light
should now come from it; and the diagnostics on, with the crosshair on a lake for a few seconds, so
the log has water probes with a named subject.

## Sharing the source: the export, and where the diagnostics went

The user asked, on 2026-09-07, for a source archive that fits Discord's upload limit, carries
none of this project's diagnostics or working material, and is organised for someone who has
never seen it. `scripts/export_source.py` is that: it stages a clean tree, cuts the
instrumentation out of the Zig sources, moves this file to `docs/irisbridge-notes.md` and the
upstream Cubyz README to `docs/cubyz-README.md`, writes a fresh root README and a
`shaderpacks/README.md` from `scripts/export/`, builds the staged tree and runs its tests, and
zips it as `CubyzReforged-source.zip`.

The instrumentation could not simply be deleted, because this file's method depends on it: the
`Log diagnostics` readbacks and the `Show G-buffer` inspector are how most of the faults above
were found, and Mellow's blue square is open with a question only they can answer. So every
piece of it now sits between a `// [diag]` line and a `// [/diag]` line - the module import,
the per-frame report in `beginFrame`, the debug view and the pixel probes in the post chain,
the thumbnail and readback helpers in `targets.zig`, the depth inspector in `pipeline.zig`,
the two settings and the two controls in the shaders screen - and the export removes those
regions and `lib/diagnostics.zig`. The regions are self-contained by construction: the
`reporting` flag that used to thread through `runPostPass` and `finishPostChain` as a parameter
is recomputed inside each fence instead (`diag.shouldReportThisFrame` is frame-stable, so that
is the same value), which is what lets a fence be cut without leaving a dangling argument. The
export's own verification build is the check that the rule was followed.

Removed outright rather than fenced, because they were never part of the method: the two
"TEMPORARY" frame captures in `renderer.zig`, one of which wrote a `capture.png` into the
working directory on the 420th frame of every run, and the `shaderSnapshotFrame` camera sweep
that went with them; the `SHADERDIAG` lines the shaders screen logged on every open; the dead
root probes; and the test folder's `run.bat` and `gifframes.py`.

## Installing packs

Drop a pack into `shaderpacks/`, as either a folder or a `.zip` — the form packs are actually
distributed in. Name it in `debug_settings.zig.zon` (or `settings.zig.zon` in a release build),
without the `.zip`:

    .shaderPack = "Nostalgia_v5.1"

Empty string restores Cubyz's own rendering.

Zips are extracted once into `shaderpacks/.cache/<name>/` and read from there. That is a deliberate
trade rather than reading the archive in place: `#include` resolution does hundreds of random
lookups across a pack, and reusing the directory reader that already serves those keeps one code
path instead of two that can disagree. An already-extracted folder always wins over a cached zip,
so unzipping by hand does what you would expect.

`shaders/` may sit at the pack root or one level down, since zipping a pack folder usually captures
the folder itself. Both are found.

Naming a pack that does not exist logs the list of packs that do. The pack loads lazily on the
first rendered frame, because building the pipeline needs a live GL context, and a failed load is
remembered so it is not retried every frame.

## Running the tests

    zig build test

That runs this mod's 185 unit tests and the engine's 73 in one go. The mod's tests live in their own
artifact because Zig collects tests per *module*, and `irisbridge` is a separate module from
`src/main.zig` — so the engine's test binary structurally cannot see them. `tests.zig` at the mod
root pulls every file into one module for that artifact to point at, and it sits at the root rather
than in `test/` because a module cannot import files above its own root source file.

That artifact deliberately does **not** import the engine's `main`. Doing so would pull in
`renderhook` and with it the `irisbridge` module, putting the same `lib/*.zig` files in two modules
at once, which Zig rejects outright. `test/main_stub.zig` stands in for the slice of `main` these
files touch, which also means the suite links in seconds rather than dragging in the C dependencies.

`test/run.bat` still drives one `zig test` per file, which is quicker when iterating on a single
file. It produces a fresh standalone executable per file, so a machine whose security settings
decline to launch unsigned binaries will refuse it — `zig build test` goes through the project's own
test runner and is the one to use.

## Testing against many packs

`test/run.bat` ends with a conformance pass over **every** pack in `shaderpacks/`. Current results,
three unrelated packs plus one duplicated as a zip to prove the archive path matches the folder
path byte for byte:

    ComplementaryUnbound_r5.8.1               30 programs   60 stages   13136 KiB  0 leftovers  4 unrecognised
    NostalgiaZip                              49 programs   98 stages    3174 KiB  0 leftovers  0 unrecognised
    Nostalgia_v5.1                            49 programs   98 stages    3174 KiB  0 leftovers  0 unrecognised
    Sildur's Vibrant Shaders v2.01 Extreme    19 programs   38 stages     691 KiB  0 leftovers  0 unrecognised

Adding a pack to that folder adds it to the test. This matters more than it looks: nearly every bug
found so far came from a convention the first pack happened to use — buffer formats hidden inside a
comment block, programs in a dimension folder, core `texture()` called on the block sampler. A
single-pack test structurally cannot see the next one of those.

The three packs exercise genuinely different shapes. Nostalgia keeps programs in `world0/`;
Sildur's keeps them at the shaders root with only `world-1`/`world1` folders; Complementary has no
root programs at all. All three are found by the same fallback rule.

**`unrecognised`** counts `.fsh` files that look like programs but matched no known program name.
It exists because silent under-discovery is the quiet failure mode here — the pack loads, renders
wrong, and nothing says why. `dh_*` (Distant Horizons) is filtered as a deliberate exclusion.
Complementary's four `clrwl_*` files are genuinely unrecognised, and correctly so: that prefix
appears nowhere in Iris either, so Iris would not load them as programs.

With no packs present the harness skips rather than failing, so the suite still runs on a bare
checkout.

## Where the chain runs

`src/renderer.zig` gained three hook calls:

- `beginFrame` at the top of `renderWorld` — captures one uniform snapshot for the whole frame and
  clears the buffers the pack asked to have cleared.
- `updateSize` in `updateViewport`.
- `runPostChain` after Cubyz's own deferred pass and before the HUD, so the pack's `final` output
  reaches the screen and the interface is not post-processed.

`importWorld` seeds `colortex0` with Cubyz's lit world from `worldFrameBuffer` (RGB16F, before its
fog and tonemap pass — the closest equivalent to what Minecraft's gbuffers leave behind) and copies
depth into all three depth textures. That stands in for the gbuffers stage until pack gbuffers
programs run on Cubyz geometry.

Two conventions packs depend on exactly, both taken from Iris:

- The fullscreen quad is `gl_Vertex.xy` in `[0,1]` with matching UVs. Packs map it to clip space
  themselves — Nostalgia's shared composite vertex shader is literally
  `gl_Position = vec4(gl_Vertex.xy*2.0 - 1.0, 0.0, 1.0)`.
- Sampler uniforms are assigned explicitly. A pack writes `uniform sampler2D colortex3;` with no
  binding qualifier, so without an explicit `glUniform1i` every sampler would read unit 0 and every
  buffer would come back as `colortex0`. OptiFine's older aliases (`gcolor`, `gdepth`, `gnormal`,
  `gaux1`-`gaux4`) map to the same units.

### The coordinate bridge, concretely

`zUpToYUp` is a -90° rotation about X:

    mc.x =  cubyz.x
    mc.y =  cubyz.z
    mc.z = -cubyz.y

`gbufferModelView = B·V·B⁻¹`, the similarity transform, because **both** the world basis and the eye
basis differ — see "Cubyz is Z-up" above, which derives it. The determinant is +1, so nothing is
mirrored; a reflection here would invert winding and flip every normal.

An earlier version of this paragraph claimed the one-sided `V·B⁻¹` and that "view space itself needs
no correction, because Cubyz's eye space is already the GL convention". Both halves are wrong, the
section above says so explicitly, and `matrix.gbufferModelView` has done the right thing since — but
the stale text sat here long enough to be re-read as evidence during a later debugging session,
which is its own lesson about leaving a corrected claim in place further down a long file.

One convention worth writing down, since it cost a wrong test: the *raw* celestial angle is 0 when
the sun is overhead, but the `sunAngle` **uniform** is that angle plus 90°, so an overhead sun
reads `0.25`. Cubyz's `getDayProgress()` is 0 at noon and 0.5 at midnight, matching the raw angle
directly.

### Uniforms with no Cubyz equivalent

Reported as documented constants rather than invented values, and listed in `unsupported` in
`lib/uniforms.zig` so the gap stays visible: `rainStrength`/`wetness` (no weather),
`nightVision`/`blindness`/`darknessFactor` (no status effects), `heldItemId`/`heldBlockLightValue`,
`hideGUI`. `moonPhase` was on this list as "no lunar cycle" until 2026-09-07; it is Minecraft's
`worldDay % 8` and the bridge keeps that counter, so it runs the eight-night cycle now
(`worldtime.moonPhase`). Held at zero it made every night a full moon, which is the brightest
night photon can draw.

`eyeBrightness` is a genuine approximation: Cubyz tracks ambient light as one scalar where
Minecraft has a sky/block pair, so both channels report the same value.

## How it attaches to the engine

`build.zig` generates `mods/renderhook.zig`, which forwards to this module when
`mods/irisbridge/lib/bridge.zig` exists and no-ops when it does not, so `src/renderer.zig` can
call the hooks unconditionally. Adding a hook means one line in `renderHooks` in `build.zig` and
the matching function in `lib/bridge.zig`.

This is deliberately *not* a `modFeature`: those generate a list of independent files for a
registry to merge, which fits worldgen generators but not a render pipeline with one entry point
and ordered per-frame hooks.

The only other engine change so far is making `main.zig`'s `c` import public, since mod modules
are given `main` and nothing else, and this one needs the GL bindings.

Caveat: the mod-absent branch of the generated hook is written but has not been exercised — the
mod has been present for every build so far.

### What a real pack corrected

Three assumptions that unit tests on hand-written snippets never would have caught:

- **Programs live in dimension folders.** Modern packs put them in `world0/` (overworld),
  `world-1/`, `world1/`, not at the shaders root. Lookup tries the dimension folder and falls back
  to the root, since both layouts are live. `#include "/…"` still resolves against the root.
- **`const` directives are parsed line-by-line, ignoring comments.** Nostalgia wraps its entire
  buffer-format block in `/* … */` so the declarations never reach the GLSL compiler, then relies
  on the loader reading them out of the comment anyway. Iris's `ConstDirectiveParser` does a raw
  line scan with no notion of comments, and matching that behaviour is what makes the difference
  between reading all 15 colortex formats and silently defaulting every buffer to RGBA8.
- **Numbered programs go to 100, not 16**, and there is a **fallback chain** between gbuffers
  programs (`gbuffers_water` → `gbuffers_terrain` → `gbuffers_textured_lit` → `gbuffers_textured`
  → `gbuffers_basic`). Packs lean on it: most ship `gbuffers_terrain` and expect blocks, water and
  damaged blocks to inherit it.

## Method notes from the water and rain session

**A classifier can invert a result, and it did.** Cubyz's physics does not tick every render frame, so
the per-frame camera delta reads *exactly* `0.0000` on roughly one frame in seven while walking — 21
of 157 samples. Bucketing a log by that number put walking samples in the "still" bucket, and there
were enough of them to flip the average: the instrument reported the precise opposite of the truth,
and it was reported to the user as a finding before they corrected it.
`diag.travelSinceLastReport` now logs `travelled=N (WALKING|still)`, integrating over the interval
rather than sampling one instant of it.

**Two instruments could not see what they were pointed at.** The once-a-second diagnostics
structurally cannot catch a symptom that only appears while walking; and the luminance thumbnail's
character ramp has `%` spanning luminance 0.46 to 1.0, so **every** sky sample printed identically
whatever it was doing. That is not a null result, it is blindness. Worse, the chosen measure was the
wrong *kind*: "foggier" is a desaturation, which can occur at constant luminance. `reportThumbnail`
now logs numeric band RGB and `B-R` as well.

**`logs/latest.log` is recreated per run, not appended** — the previous run becomes
`logs/ts_<stamp>.log`. Two analyses of "the same" line range silently read two different runs.

**Read the whole file.** A confident conclusion that Complementary discards the water texture by
design came from reading 45 lines of a 310-line file; the mechanism was 150 lines further down.

**The recording is the instrument that works.** `test/gifframes.py` plus a few dozen lines of Python
over the PNGs settled in one pass what eight once-a-second captures could not — hundreds of samples,
real pixels, and the ability to answer *where* on screen something happens. Frame-to-frame pixel
difference is also a motion proxy that cannot be fooled by the tick rate, and it makes menus obvious:
they read as exactly 0.00 for dozens of frames.

**Log the consequence of a fix.** The fluid-height change looked like it had failed. The count of
affected blocks had never been logged, so "did nothing" and "was the wrong idea" were
indistinguishable — both leave the image identical.

**The user's report outranks your measurement.** Three times in one session the analysis contradicted
what they described — which state was the bad one, whether the water texture was missing, what the
flicker was — and three times they were right. When a measurement disagrees with the person looking at
the screen, suspect the measurement.

**Do not write Zig through shell heredocs.** Escape sequences get mangled: `\\` collapses to `\` and
`\t` becomes a literal tab, producing invalid string literals. One such repair corrupted an unrelated
prologue and took four programs down at once, which cost two launches.

## Known limits (not bugs)

- The `block.properties` mapping is a name match, not a semantic one. A Cubyz block whose name has
  no Minecraft counterpart — `glimmergill`, `ferrock`, `voidstone` — gets `mc_Entity` 0 and renders
  as ordinary terrain, which is the right default but not the same as a pack author having chosen
  it. Nothing can fix that in general; a per-pack override file could fix it case by case.
- Custom sky/cloud programs assume Minecraft's sky geometry, which Cubyz does not have.
- `gbuffers_hand`, `gbuffers_weather`, `gbuffers_armor_glint` have no Cubyz counterpart yet.
- Iris compute-shader extensions and `.csh` programs are out of scope for now.
- **`ANISOTROPIC_FILTER` cannot work here, and at anything above `0` it takes the terrain program
  down with it.** Complementary's `VERYHIGH` and `ULTRA` profiles set `ANISOTROPIC_FILTER=8`, and
  `program/gbuffers_terrain.glsl` then calls `textureAF(tex, texCoord)` against
  `vec4 textureAF(sampler2D texSampler, vec2 uv)`. `tex` is `#define`d to Cubyz's
  `sampler2DArray`, so the driver rejects it — `error C1102: incompatible type for parameter #1`.

  The per-call-site sampler redirect cannot reach this: it rewrites *known sampling functions*
  (`texture`, `texture2D`, `textureLod`, …) whose first argument names the block texture, and this
  is the pack passing the sampler into **its own helper**. Since 2026-09-04 a helper that only
  *samples* its parameter gets a `sampler2DArray` overload (`glsl.SamplerFunction`, under "The
  fourth set" above), which is what Bliss needed. `textureAF` does not qualify: its body reads
  `textureSize` and arithmetic off the sampler, and an array copy of it would not compile, so the
  transformer leaves it alone on purpose rather than fail the program with a dead overload.

  It would be wasted work anyway: `textureAF` exists to filter *within an atlas sprite*, and its
  first act is to compute `spriteBounds`. Cubyz has one layer per texture, so the feature has nothing
  to operate on. Keep it at 0.
- **`COLORED_LIGHTING` above 0 makes the pack draw a full-screen error.** `program/final.glsl:27` is
  `#if COLORED_LIGHTING > 0 && (!defined IS_IRIS || !defined IRIS_FEATURE_CUSTOM_IMAGES)`, and
  Complementary's `VERYHIGH`/`ULTRA` set it to 256/512. `IS_IRIS` is supplied;
  `IRIS_FEATURE_CUSTOM_IMAGES` is not, because custom images are compute-shader-written and that is
  the bullet above.

  **Do not silence this by defining the macro.** The pack would then bind samplers to images nothing
  writes, which is undefined usage rather than a black read — the same trap as the unassigned
  samplers in "It renders". The pack's refusal is correct behaviour given what this bridge honestly
  advertises, and the fix is `COLORED_LIGHTING = 0`.

  Worth noting how these two present: a shaderpack profile is not a quality dial the host can ignore,
  which this file already recorded twice for `ResolutionScale`. This is the third instance and the
  loudest, because one of the two failures **silently drops `gbuffers_terrain`** — the load continues
  with a warning, `terrainPass` stays null, and the frame quietly reverts to Cubyz's own terrain
  shading under the pack's post chain. Anything measured in that state is measuring a different
  pipeline.

