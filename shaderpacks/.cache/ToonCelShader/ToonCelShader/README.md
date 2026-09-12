# Toon Cel Shader

The odd one out in this series: instead of chasing realism, this pack
flattens lighting into discrete bands and draws real screen-space
outlines around silhouettes and hard edges - the actual technique
behind cel-shaded game rendering, not just a color filter.

## What makes this one technically different

Every other pack in this series is purely forward-shaded: each
gbuffers stage computes final lit color and that's that. This pack
needs one more piece of information to draw outlines - each surface's
**normal** - so `gbuffers_terrain`/`entities`/`water`/`hand` now write
to *two* render targets instead of one: `colortex0` (the shaded
color, same as before) and `colortex1` (the view-space normal). The
`composite` pass then reads both, plus the depth buffer, and looks
for sharp jumps in either between neighboring pixels - that's where
outlines get drawn.

## Features

- **Banded lighting** (`LIGHT_BANDS`, default 3) - light is quantized
  into discrete steps instead of a smooth gradient
- **Screen-space outlines** - real depth+normal edge detection, not a
  simple color-based sketch filter; tunable thickness and sensitivity
- **Hard-edged shadows** - no PCF softening, matches the flat/graphic
  look on purpose
- **Rim light** on entities - stylized fresnel glow around silhouettes
- Flat, saturated toon water tint
- Optional posterize pass (off by default - looks great on simple
  scenes, can look muddy on busy/detailed ones, your call)

## Requirements

Minecraft 26.2, Iris 1.11.0+, Sodium, OpenGL (not the Vulkan
renderer). Runs comfortably on mid-range hardware - it's cheaper than
the Cinematic Realism pack in this series (hard shadows, no bloom, no
volumetrics), even with the extra normal buffer.

## Installation

Same as the others: drop the zipped file (don't extract it) into your
shaderpacks folder, select it in Options → Video Settings → Shader
Packs.

## Tuning outlines

If outlines look too thick/noisy or too thin/sparse:
- `OUTLINE_THICKNESS` - how many pixels wide the edge-sampling kernel is
- `OUTLINE_DEPTH_SENSITIVITY` - higher = more depth discontinuities count as edges
- `OUTLINE_NORMAL_SENSITIVITY` - higher = fewer normal discontinuities count as edges (counterintuitive direction - it's a threshold, raising it makes it *stricter*)

Foliage and other alpha-cutout geometry with lots of small internal
normal variation (leaves, tall grass) can get a slightly busy/noisy
outline look - if that bothers you, lowering `OUTLINE_NORMAL_SENSITIVITY`'s
strictness (i.e. raising the number) is the first thing to try.

## Known limitations

- Outline detection is 2D screen-space, so it can't tell the
  difference between "true silhouette edge" and "two unrelated
  objects that happen to line up at this pixel" - rare in practice,
  but it's a known limitation of the technique generally, not a bug.
- The extra normal buffer write means this pack can't be trivially
  merged with the others in this series (they don't have a colortex1
  to read from) - it's a standalone pack, not a toggle on top of
  another one.
