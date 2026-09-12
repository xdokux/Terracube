# Simple Iris Shaders

A small, forward-shaded Iris shader pack built around one goal: look
noticeably better than vanilla without tanking your framerate -
including on integrated graphics like an **Intel UHD 630**.

Inspired by the philosophy of packs like **Sildur's Enhanced Default**
(lightweight, forward-shaded, no deferred G-buffer pipeline) rather
than heavier packs like Complementary/BSL. This is intentionally *not*
trying to be those - no volumetric clouds, no colored/PBR shadows, no
screen-space reflections, no per-pixel raytracing gimmicks.

## What's included

- Directional sun/moon lighting with a smooth day-night-sunset blend
- Shadow mapping with configurable resolution and PCF softening
- Wavy water (vertex-animated, essentially free performance-wise) -
  **no water reflections**, by design
- Underwater fog + normal fog, tuned to blend with vanilla's horizon
- Volumetric god rays / light shafts, raymarched against the shadow
  map, capped and dither-jittered to stay cheap
- A light filmic tonemap + saturation pass

## What's deliberately NOT included (yet)

Kept out to hit the "simple, easy, reasonable, fast on weak hardware"
brief. See CHANGELOG.md for candidates to add later:
- Water/scene reflections (screen-space or otherwise)
- Colored/translucent shadows (e.g. tinted light through stained glass)
- PBR resource pack support (`_n`/`_s` normal/specular textures)
- Volumetric clouds, volumetric fog
- Bloom, depth of field, motion blur, chromatic aberration
- Ambient occlusion

## Requirements

- **Minecraft: Java Edition 26.2** ("Chaos Cubed"). Note Mojang moved
  to year-based versioning in 2026, so this is *not* "1.26.2" - that
  version number doesn't exist. If you're on a different 26.x release
  it will very likely still work (the shader pipeline stage names and
  uniforms haven't changed since 26.1), but 26.2 is what this was
  built and reasoned about against.
- **Iris 1.11.0+** (the first release with 26.2 support). Get it from
  Modrinth or CurseForge.
- **Sodium** (any Iris-compatible build) - fully supported, this pack
  assumes you're running Iris+Sodium together.
- Run on **OpenGL**, not the new experimental native Vulkan renderer
  introduced in 26.2 - Iris does not run shader packs under Vulkan at
  all (shaders silently disable if you switch to it). If you've
  enabled Vulkan in Video Settings, switch back to OpenGL first.

## Installation

1. Install Fabric or NeoForge, then Iris (which will also require/
   bundle Sodium depending on your loader).
2. Download this pack as a `.zip` - **do not unzip it**.
3. Open Minecraft, go to **Options → Video Settings → Shader Packs →
   Open Shader Pack Folder**.
4. Drop the `.zip` into that folder.
5. Back in the Shader Packs screen, select it from the list.

## Quality profiles

Pick a profile from the dropdown in the Shader Packs screen (top of
the options list once the pack is selected), or fine-tune individual
sliders yourself afterward - manual slider changes override the
profile's defaults.

| Profile | Target hardware | Shadow res | God rays | Notes |
|---|---|---|---|---|
| `igpu` | Intel UHD 630/620, Vega 8, similar integrated GPUs | 512, 48 blocks | Off | Hard-tuned for bandwidth/fill-rate-limited hardware, not just "low settings" - see below. |
| `normal` | GTX 1660 / RX 5600 and up | 1024, 96 blocks | On, 12 steps | The "just looks nice" default. |

If you're not sure which to pick: if your GPU doesn't have its own
dedicated video memory (i.e. it's the graphics built into your CPU),
start with `igpu`.

### Why `igpu` isn't just "normal, turned down"

Integrated GPUs like the UHD 630 are typically **bandwidth- and
fill-rate-bound**, not compute-bound - they share system RAM instead
of having dedicated VRAM, and have much weaker per-pixel throughput
than even entry-level discrete cards. So the `igpu` profile:

- Cuts the shadow map to 512 and shadow distance to 48 blocks, since
  the shadow pass is a *second full geometry pass* and iGPUs are
  especially sensitive to draw-call/geometry throughput.
- Drops PCF shadow softening to a single hard sample (no multi-tap
  filtering), since each additional tap is a full extra texture fetch
  per fragment.
- Disables god rays entirely rather than just reducing steps - a
  raymarch loop is close to the worst case for hardware with weak
  parallelism, so this is the first thing cut, not the last.

You can still hand-tune any individual slider after picking `igpu` as
a starting point if you want to push a setting back up and see how it
performs on your specific hardware.

## Known limitations

- God rays are a screen-space/shadow-map raymarch, not true 3D
  volumetric scattering - they look right through gaps in geometry
  (tree canopies, window bars) but won't produce, e.g., visible dust
  motes in open air.
- Water waves are purely a vertex-shader displacement; the "wet
  reflective" look you may know from other packs is intentionally
  absent (no reflections at all, per project scope).
- No PBR resource pack support - `_n`/`_s` textures are simply
  ignored, not read.
- Tested against Iris 1.11.0's shader-stage/uniform behavior on 26.2;
  if a future Iris release renames a uniform or stage, the affected
  effect (most likely the god-ray raymarch, since it uses the most
  matrices) is the one to check first.

## File layout

```
shaders/
  shaders.properties       profiles, shadow map size, options menu
  shadow.vsh / .fsh        depth-only shadow map pass
  gbuffers_terrain.*        opaque terrain, forward-shaded + shadows
  gbuffers_entities.*       mobs/players, same lighting model
  gbuffers_water.*          wavy translucent water/glass, no reflections
  gbuffers_hand.*           held item, simplified (no shadow sampling)
  composite.*               god rays, raymarched against the shadow map
  final.*                   tonemap + saturation, last stage before screen
  lib/
    settings.glsl           every quality #define, in one place
    common.glsl              fog/math/saturation helpers
    lighting.glsl            sun/moon direction + day-night color blend
    shadows.glsl             shadow-map projection + PCF sampling
    water.glsl               vertex wave displacement function
```
