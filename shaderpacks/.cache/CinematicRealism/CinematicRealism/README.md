# Cinematic Realism

A forward-shaded Iris pack aimed at a warm, golden-hour, "cinematic
realism" look, tuned for high-end hardware. Third pack in this series
- see the other two for a lightweight iGPU-focused option and a
near-zero-cost vanilla+ color grade.

## Features

- Shadow mapping with a **distortion-based pseudo-cascade** (see
  "About the shadow technique" below - this is not true multi-map
  CSM, which Iris/OptiFine's pipeline doesn't support)
- Golden-hour sky gradient, glowing sun/moon disc, drifting 2D
  layered-noise clouds
- Height-based fog (thicker in valleys/caves than on mountaintops)
- Real two-pass separable HDR bloom (RGBA16F intermediate buffer, so
  bright sources don't clip before blurring)
- Clear blue water tint, procedural vertex waves, rain ripple normal
  perturbation, and patchy rain puddles on terrain
- An explicit ambient light floor so caves and night-time terrain
  never render pure black

## About the shadow technique

"Cascaded shadow maps" in the strict sense (multiple shadow maps at
different resolutions/distances, blended by depth) aren't something
the Iris/OptiFine single-shadowtex pipeline supports. What this pack
does instead - and what packs like BSL/Chocapic/Sildur's actually
mean when they advertise "high quality shadows" - is **distort the
single shadow map's UV space** so texel density is much higher near
the camera and falls off with distance (`SHADOW_DISTORTION` in
`lib/settings.glsl`). It reads as cascade-like quality falloff
without needing multiple render targets. The distortion is applied
identically in `shadow.vsh` (rendering the map) and
`lib/shadows.glsl` (sampling it) - if you ever edit one, edit both,
or shadows will misalign with geometry.

## About the colored lighting

This is the one feature that's a real approximation, and it's worth
knowing why: true dynamic colored point lights (arbitrary RGB per
placed light source, correctly shadowed and falling off per-light)
need a deferred renderer with a light-accumulation buffer - a genuine
second project, not something to bolt onto a forward-shaded pack
without doing it properly. What's here instead is vanilla's own
block-light lightmap channel, tinted warm, with a few block-ID-based
hue nudges (torches, lava, redstone - see `block.properties` and
`lib/lighting.glsl`). It looks colored-ish at a glance; it won't hold
up if you go looking for correctly-falling-off individual light
sources. Extend the ID table in both files together if you want more
block types hinted.

## Requirements

- Minecraft: Java Edition 26.2, Iris 1.11.0+, Sodium, OpenGL (not the
  experimental Vulkan renderer - Iris doesn't run shaders under it)
- A discrete GPU. This pack is not tuned for integrated graphics - if
  that's your hardware, use the `SimpleIrisShaders` pack instead.

## Installation

Drop the `.zip` (unzipped file, not extracted) into your shaderpacks
folder via Options → Video Settings → Shader Packs → Open Shader Pack
Folder, then select it from the in-game list.

## Options menu groups

Shadows · Ambient/colored light · Sky/golden-hour · Clouds · Height
fog · Bloom · Rain/puddles · Exposure - all grouped in that order in
the in-game Shader Options screen.

## Known limitations

- Clouds are a flat 2D noise plane, not a raymarched 3D volume - true
  volumetric clouds (light scattering through a 3D density field) is
  a substantially heavier effect; this is the "volumetric-style"
  compromise the brief allowed for.
- No PBR resource pack support.
- Colored lighting is the block-ID-hint approximation described
  above, not per-light-source RGB.
- Bloom threshold/intensity defaults are tuned for a fairly bright
  golden-hour scene; night skies with very few bright pixels will
  show comparatively little bloom, which is expected.

## File layout

```
shaders/
  shaders.properties
  block.properties          maps modern block IDs for mc_Entity lookups
  shadow.vsh / .fsh          depth-only pass, with distortion applied
  gbuffers_terrain.*          shadows, golden-hour light, puddles, height fog
  gbuffers_entities.*         same lighting model, entity color tint
  gbuffers_water.*            waves, rain ripples, clear blue tint
  gbuffers_hand.*             simplified, no shadow sampling
  composite.*                 procedural sky, sun/moon glow, clouds
  composite1.*                bloom bright-pass + horizontal blur -> colortex1
  composite2.*                vertical blur + combine -> colortex0
  final.*                     exposure, filmic tonemap, saturation
  lib/
    settings.glsl              every #define, one place
    common.glsl                 math/noise/fog helpers
    lighting.glsl                sun/moon color, ambient floor, light tint
    shadows.glsl                 distortion + PCF sampling
    water.glsl                   waves, rain ripples, puddle mask
    sky.glsl                     sky gradient, sun glow, cloud density
```
