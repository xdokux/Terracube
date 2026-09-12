# Vanilla Dynamic Shadows

Minimal, additive-only: vanilla Minecraft's own look, plus dynamic
shadows and god rays. Nothing else changes - no color grading, no
tonemap curve, no bloom, no sky/cloud rewrite, no water waves.

## Why this pack looks the way it does

A few requirements pulled against each other or needed a specific
real technique rather than the obvious one. Worth knowing before you
tune the sliders:

**"Pixel-perfect" vs. "fast on a UHD 630"** - these trade off directly
through shadow resolution. Default is `SHADOW_RES 1024` /
`SHADOW_DISTANCE 72.0`, tuned for the UHD 630 first. That's crisp for
nearby blocks; it will not look pixel-perfect at long range the way a
2048+ shadow map would. Raise `SHADOW_RES` if you're on better
hardware and want that.

**"No jittery shadows"** - the actual fix here isn't blur. Shadows
this pack draws use:
1. **Hardware shadow-compare sampling** (`sampler2DShadow` +
   `shadowHardwareFiltering = true`) - the GPU bilinearly filters the
   pass/fail *result* across the 4 nearest shadow texels in a single
   fetch, which smooths the edge's position frame-to-frame without
   softening it into a blur.
2. **Normal-offset bias** instead of a large depth bias - the sample
   point is pushed slightly along the surface normal, in world space,
   before it's tested against the shadow map. This is what actually
   kills both shadow acne and swimming; a bigger depth bias would
   have caused visible peter-panning (shadows detaching from objects)
   instead of fixing anything.
3. **No shadow-map distortion.** An earlier pack in this series used
   a distortion warp for pseudo-cascaded shadows, but that warp's
   effective texel density shifts continuously as you move - a real
   source of instability that has no place in a "no jitter" pack.
4. **The held item doesn't sample shadows at all** - it's the
   worst-case surface for shadow flicker (close to camera, moves with
   every look-around), so it's simplest and steadiest to just light
   it without.

**"Tone shouldn't change as I look around"** - there is no
view-direction-dependent term anywhere in this pack: no fresnel, no
rim light, no specular highlight, no auto-exposure/eye-adaptation.
Every lighting term is a function of world-space geometry and the
sun/moon direction only. Rotating the camera changes what you see,
not how bright/what color it's lit.

**"God rays visible even off-screen"** - this rules out the common
"radial blur toward the sun's screen position" technique (breaks the
moment the sun isn't in frame). This pack raymarches from the camera
along each pixel's view ray instead, sampling shadow-map occlusion at
each step - a purely world-space test, so shafts through gaps in
geometry show up regardless of where the sun/moon icon itself is.

**"No insane bloom"** - there's no bloom pass at all. God ray
intensity defaults low (`GODRAY_INTENSITY 0.28`) and is additive only.

## Requirements

Minecraft 26.2, Iris 1.11.0+, Sodium, OpenGL (not the Vulkan
renderer - Iris doesn't run shaders under it).

## Installation

Drop the zipped file (don't extract it) into your shaderpacks folder
via Options → Video Settings → Shader Packs → Open Shader Pack
Folder, then select it in-game.

## Options

- `SHADOW_RES` / `SHADOW_DISTANCE` - the main quality/performance lever
- `NORMAL_OFFSET_TEXELS` - shadow acne/peter-panning trade-off; raise
  slightly if you see acne (dark speckling on lit faces), lower if
  shadows look detached from their casters
- `GODRAYS`, `GODRAY_STEPS`, `GODRAY_DISTANCE`, `GODRAY_INTENSITY`

## Known limitations

- "Pixel-perfect" is relative to the chosen shadow resolution/distance
  - it's crisp, not infinite-resolution. See the trade-off note above.
- God rays are capped at `GODRAY_DISTANCE` blocks from the camera by
  design (a near-field atmospheric effect, not full-scene volumetric
  fog) - very distant light shafts won't extend further than that.
- No shadows on the held item, by design (see above).
