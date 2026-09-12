# Changelog

## v0.1.0 - Initial build

- Dynamic shadows: hardware-filtered (`sampler2DShadow`) single-tap
  sampling with normal-offset bias, no distortion warp, no PCF loop
- God rays: per-pixel view-ray raymarch against the shadow map
  (screen-position-independent - visible with the light source
  off-screen)
- Strictly world-space lighting: no fresnel/rim/specular, no
  auto-exposure - verified by a scripted scan for view-direction terms
  before shipping
- No bloom, no tonemap curve, no water/sky rewrite - additive-only
  changes to vanilla's look
- Held item excluded from shadow sampling to avoid first-person
  shadow flicker

Verified before shipping: no duplicate uniform declarations across
any include chain, balanced braces/parens/preprocessor directives,
and a scripted scan confirming no `viewDir`/`reflect(`/fresnel/
`centerDepthSmooth` terms exist anywhere in the pack.

## Candidates for v0.2.0

- A second, higher shadow-distance profile for discrete GPUs, since
  this build is tuned UHD-630-first
- Optional very-subtle SSAO (off by default) for players who want a
  bit more depth without touching the "stay simple" default
- Investigate whether Iris exposes any shadow-camera texel-snapping
  hook in a future version - would be a more complete fix for
  sub-pixel shadow shimmer than normal-offset bias alone, which
  addresses acne/swimming but not true shadow-camera texel snapping
