# Changelog

## v0.1.0 - Initial build

- Distortion-based pseudo-cascade shadows (2048 default, PCF up to 8 taps)
- Golden-hour sky gradient, sun/moon glow, layered 2D clouds
- Height-based fog
- Real two-pass separable HDR bloom (RGBA16F intermediate buffer)
- Clear blue water tint, vertex waves, rain ripples, patchy puddles
- Ambient light floor (fixes pitch-black caves/night)
- Block-ID-hinted warm/colored block light (torches, lava, redstone)

## Known bugs fixed during initial build (kept here for history)

- Found and fixed two duplicate `uniform float rainStrength;`
  declarations (in `gbuffers_terrain.fsh` and `gbuffers_water.fsh`) -
  both files already got it via their `#include "lib/lighting.glsl"`.
  This is the same bug class that broke terrain rendering in an
  earlier pack in this series (double-declared symbols across
  `#include`s), caught this time by scripting a duplicate-uniform
  check across every file's include chain before shipping.

## Candidates for v0.2.0

- Real deferred colored point lights (would need a proper
  light-accumulation buffer - a genuinely separate undertaking from
  the block-ID-hint approximation currently in place)
- 3D raymarched volumetric clouds
- PBR resource pack support (`_n`/`_s` textures)
- Half-res bloom buffer for lower cost at similar quality
- A lower-hardware profile (this pack is currently single-tier,
  high-end only)
