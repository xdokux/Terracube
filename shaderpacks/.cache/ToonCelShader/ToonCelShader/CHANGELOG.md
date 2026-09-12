# Changelog

## v0.1.0 - Initial build

- Banded/quantized toon lighting (2-5 configurable bands)
- Screen-space outline pass using depth + view-space normal
  discontinuity detection (real G-buffer normal write, first pack in
  this series to need one)
- Hard-edged single-tap shadows
- Rim light on entities
- Flat saturated toon water tint

Verified before shipping: no duplicate uniform declarations across
any file's include chain, balanced braces/parens/preprocessor
directives, and every DRAWBUFFERS-tagged fragment shader's gl_FragData
writes match its declared target count.

## Candidates for v0.2.0

- Outline color/thickness that scales with distance (currently flat)
- A second, thinner "detail" outline pass for internal edges vs. silhouette
- Toggleable posterize-in-HSV (current posterize is per-channel RGB,
  which can shift hue slightly at low level counts - a v2 could
  posterize value only, preserving hue)
- Stylized painted-cloud sky to match the flat aesthetic (currently
  uses vanilla sky rendering, untouched)
