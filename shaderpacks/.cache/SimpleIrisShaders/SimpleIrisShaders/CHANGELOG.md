# Changelog

## v0.1.0 - Initial build

First working version. Scope deliberately kept tight around
performance on integrated graphics (Intel UHD 630 target) plus a
handful of features that read as a clear visual upgrade over vanilla:

- Shadow mapping (512/1024/2048, PCF 1/2/4 taps)
- Directional sun/moon lighting, day-night-sunset color blend
- Wavy, non-reflective water (vertex-displacement only)
- Underwater + regular exponential fog
- Volumetric god rays (shadow-map raymarch, dithered, capped steps)
- Filmic tonemap + saturation pass
- `igpu` and `normal` quality profiles

## Candidates for a future v0.2.0 (not yet implemented)

Roughly in the order they'd likely matter to most users:

- **True half/quarter-resolution offscreen buffer for god rays**, with
  bilateral upsampling - would let `normal`/a future `high` profile
  raise visual quality further without a 1:1 cost increase. Needs a
  sized render target + an extra composite pass to upsample.
- **Ambient occlusion** (cheap depth-based SSAO), off on `igpu`, on for
  `normal` and above.
- **A `high` profile** above `normal` for stronger discrete GPUs, once
  there's more than one toggle worth turning up.
- **Cheap water reflections** (screen-space, water-surfaces-only) as
  an explicit opt-in toggle - was cut from v0.1.0 scope on purpose,
  not forgotten.
- **Colored/translucent shadows** (light tinted by stained glass) as
  an "ultra" toggle - doubles shadow-pass cost, so profile-gated only.
- **Basic PBR support** (reading OptiFine-spec `_n`/`_s` textures) for
  resource packs that ship them.
- **Bloom** - cheap single-pass bright-pass blur, `normal`+ only.

## Known issues to watch

- God-ray raymarch cost scales linearly with `GODRAY_STEPS` - if a
  future step count increase is added to `normal`, re-benchmark on a
  GTX 1660-class card before shipping it as the new default.
- Shadow PCF texel-size math in `lib/shadows.glsl` reads `SHADOW_RES`
  from `lib/settings.glsl`; this must always be kept equal to the real
  `shadowMapResolution` engine property set in `shaders.properties`
  for each profile, or PCF sample spacing will be wrong. Worth adding
  a build-time check for this if the pack grows more profiles.
