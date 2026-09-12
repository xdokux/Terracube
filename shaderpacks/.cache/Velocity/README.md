# Velocity

Velocity is a fork of [mellow](https://codeberg.org/TheCMK/mellow-shader) by TheCMK,
tuned for the **FAST profile** with several additions on top of mellow's solid
optimized base:

- **Sun Rays** — a dedicated crepuscular-rays post-process pass (`composite1`)
  that traces a short screen-space march from each pixel toward the sun and
  produces visible light shafts on clear days, not only in fog. The effect is
  decoupled from atmospheric fog so you actually see the rays during normal
  gameplay, and it falls back to subtle moon rays at night.

- **Improved Dynamic Shadows** — dynamic shadows are now enabled by default in
  the FAST profile, at 1024 shadow-map resolution with a 12-tap Vogel-disk PCF
  filter and a cheap PCSS-style penumbra estimate. Shadow edges are softer and
  more realistic, with a tuned normal-based bias that reduces both acne and
  peter-panning at higher resolutions.

- **Modern Lighting** — a Complementary-reimagine-style lighting model with
  wrapped diffuse (softens the terminator), ambient SSS (warm foliage
  back-light), directional sky ambient (hemisphere biased toward the sun), and
  a subtle sky bounce. A PBR-free sun glint adds a fake specular highlight on
  flat terrain for users without a labPBR resourcepack.

- **Distinct Torch Light** — torches, lanterns, and other block-light sources
  get their own identity instead of sharing mellow's flat orange. A warm
  flickering flame color with a temperature shift (white-hot near the source,
  warm orange at distance) and per-source flicker so torches don't all pulse
  in sync. Tunable via the **Colors → Other → Velocity Torch Light** screen.

- **Enhanced Rain** — rain particles get motion-blurred streaks (instead of
  flat points), a denser rain atmosphere with fog that reduces visibility
  during storms, and bright splash speckles on wet ground. Tunable via the
  **Sky → Velocity Rain Settings** screen.

- **Cartoon Wind Streaks** — occasional wind streaks that float across the sky
  like clouds, tracing a swirl pattern as they drift. Rendered in world space
  (not stuck to the screen), so they're occluded by terrain and float at a
  fixed altitude. More frequent during the day, rarer at night. Purely
  cosmetic. Tunable via the **Camera Effects → Velocity Wind Streaks** screen.

- **Beautiful Water** — a multi-octave procedural normal map, proper Schlick
  Fresnel, a tight GGX sun specular highlight, Beer-Lambert depth absorption
  (shallow water stays clear, deep water goes dark blue-green), and shoreline
  foam. Quality presets let you trade visuals for perf with one slider.

- **Improved Foliage Wind** — replaces mellow's single-sine swaying with
  multi-octave wind, gusts, per-plant phase variation, height-based bending,
  and plant-type-aware stiffness. Shared across terrain, water, and shadow
  passes so foliage shadows stay in sync.

All mellow optimizations (low-cost gbuffers, lightmap-based shadow fallback,
minimal post-processing) are preserved. The FAST profile is still the
recommended default for low-end hardware. Cave/night play is especially cheap
— sun rays, ambient SSS, sun glint, and dynamic shadows all skip when there's
no sky exposure.

The original mellow author (TheCMK) has asked that forks not use the "mellow"
name or any of its assets. Velocity is a distinct name; please credit TheCMK
if you share this fork.

## New options

| Option | Default | Description |
|--------|---------|-------------|
| `SUNRAYS` | On | Enables the dedicated sun-rays post-process pass. |
| `SUNRAYS_QUALITY` | 24 | Number of samples per pixel for the ray march. 12–96. |
| `SUNRAYS_INTENSITY` | 0.55 | Overall brightness of the rays. |
| `SUNRAYS_DECAY` | 0.86 | Per-sample decay. Higher = tighter rays near the sun. |
| `SUNRAYS_EXPOSURE` | 1.0 | Final multiplier, useful for matching your tonemap. |
| `SHADOW_PENUMBRA` | 1.0 | Scales how soft shadow edges get near occluders. |

All sun-ray options live under the **Fog** screen in the shader options menu.
The new penumbra slider lives under **Terrain & Lighting → Shadow Settings**.

## Profile matrix

| Profile | Sun Rays | Godrays (Fog) | Dynamic Shadows | Bloom | TAA | SMAA | SSAO |
|---------|:--------:|:-------------:|:---------------:|:-----:|:---:|:----:|:----:|
| Fast    |    ✓     |       ✓       |        ✓        |   ✗   |  ✗  |  ✗   |  ✗   |
| Fancy   |    ✓     |       ✓       |        ✓        |   ✓   |  ✗  |  ✗   |  ✗   |
| Fabulous|    ✓     |       ✓       |        ✓        |   ✓   |  ✓  |  ✓   |  ✓   |

## Installation

1. Download `Velocity.zip`.
2. Copy it to your `.minecraft/shaderpacks` folder.
3. In Minecraft, go to **Options → Video Settings → Shader Packs**, select
   **Velocity**, and click **Apply**.
4. (Recommended) Open the shader options and pick the **Fast** profile — sun
   rays and dynamic shadows are already enabled there.

Requires [Iris](https://www.irisshaders.dev/) (or OptiFine with minor caveats).

## Credits

- **mellow** by [TheCMK](https://codeberg.org/TheCMK) — the entire base this
  fork is built on. Please go try the original if you haven't already.
- The mellow `LICENSE` (MIT) and `LICENSE-APACHE` are kept intact in this
  repository, as required. All Velocity-specific additions are released under the
  same MIT license that mellow uses.
- Sun-ray algorithm adapted from Kenny Mitchell's "Volumetric Light Scattering
  in Post-Processing" (GPU Gems 3).
- PCSS-style penumbra estimate inspired by Percentage-Closer Soft Shadows
  (Fernando, 2005), simplified for FAST-profile hardware.

## Source

This fork was created from mellow commit `1c16f22`. The mellow shader is
licensed under the MIT license; see `LICENSE` for the full text. The CMK has
asked that forks not use the "mellow" name or any of its assets (screenshots,
logo, etc.) — please credit TheCMK if you share this fork.
