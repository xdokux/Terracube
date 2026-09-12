# Halcyon - a deferred Iris shader pack inspired by Complementary Shaders & Photon

Built for: Fabric 0.16.14, Minecraft 1.21.4, Sodium 0.6.13, Iris 1.8.8.

This is an **original implementation** of techniques those two packs are known
for - it does not contain or copy their source code (Complementary's isn't
publicly published anyway, and Photon's CC0 code exists but wasn't used here).
What's "borrowed" is the architecture and algorithm choices, written from
scratch:

| Feature | Inspired by | What it does here |
|---|---|---|
| Deferred G-buffer + resolve | Both | Opaque lighting computed once in `deferred.fsh`, not per-gbuffer-program |
| Colored shadows through glass | Both | `shadowcolor0` tints light instead of just blocking it |
| Raymarched volumetric light shafts | Photon | `composite.fsh` marches the shadow map along the view ray |
| Screen-space water reflection | Complementary | Simplified raymarch in `gbuffers_water.fsh` |
| Procedural sky clouds | Photon (custom-rendered, non-vanilla clouds) | fbm noise, no texture assets |
| Filmic tonemapping | Both | ACES approximation in `final.fsh` |

## Install

Copy the `Halcyon` folder into `.minecraft/shaderpacks/` so you get
`.minecraft/shaderpacks/Halcyon/shaders/...`, then select it from
Options > Video Settings > Shader Packs.

## Pipeline order (this is the part that makes "deferred" work)

```
shadow.*              -> depth + color from the sun/moon's POV (colored shadow data)
gbuffers_terrain.*     -> writes G-buffer only: colortex0=albedo, colortex1=normal, colortex2=lightmap uv
deferred.*             -> reads the G-buffer + depth, resolves ALL opaque lighting in one pass,
                           writes the lit result back into colortex0
gbuffers_water.*        -> forward-rendered AFTER deferred, so it can read colortex0 (the lit
                           opaque scene) for refraction and reflection
gbuffers_sky*, gbuffers_textured/basic -> unlit-by-deferred passes (sky is pre-final; entities/
                           particles are forward-lit separately, see limitations)
composite.*             -> volumetric light shafts + distance fog
composite1.*            -> bloom (bright-pass + blur)
final.*                 -> exposure, ACES tonemap, gamma, vignette
```

`deferred` is a distinct Iris/OptiFine program stage specifically because it
runs *between* opaque and translucent geometry - that's what lets water read
an already-fully-lit scene for its reflections/refraction instead of a raw
unlit G-buffer.

## Where I simplified vs. a "real" pack, and why

Being upfront about this so nothing surprises you in testing:

- **Water doesn't self-shadow.** Computing water's own shadow needed the same
  camera-relative "feetPlayerPos" space used everywhere else, but the water
  vertex shader only has view-space position available after the wave
  displacement. Rather than ship a subtly-wrong shadow transform, I left
  direct lighting on water unshadowed. Fixable by also passing a
  `feetPlayerPos` varying from `gbuffers_water.vsh` if you want it.
- **SSR has no fallback sky match.** When the reflection raymarch misses, it
  falls back to a flat two-color gradient that is *not* the same code as the
  actual procedural sky - so reflections of the sky on distant water won't
  perfectly match what's overhead. Real packs usually render a small
  mip-mapped "sky capture" texture earlier in the frame for this; that's a
  reasonable next addition.
- **Bloom is single-pass**, sampling a 5x5 kernel directly off the full-res
  buffer rather than the downsample/blur/upsample chain Complementary/Photon
  use. It'll look softer/cheaper and is more expensive per-pixel than a
  proper mip chain would be at higher resolutions.
- **No auto-exposure.** `final.fsh` uses a constant `EXPOSURE`. Real
  eye-adaptation needs a persistent luminance buffer averaged across frames,
  which means ping-ponging a 1x1 (or small) render target - didn't want to
  ship that without being able to test it compiles and behaves across
  frames.
- **Entities/particles/hand don't receive shadows or the deferred lighting
  model** - they're forward-lit with just the vanilla lightmap
  (`gbuffers_textured`/`gbuffers_basic`), same as the previous foundation
  pack. Folding them into the deferred G-buffer is the natural next step.
- **Cloud plane is a flat projected layer**, not a true volumetric raymarch
  through a 3D noise field (which is what Photon actually does for its
  clouds). It fades near the horizon specifically to hide the visual
  artifacts a flat-plane approximation gets at grazing angles.

## Tuning knobs

- `deferred.fsh` / `gbuffers_terrain.fsh`: `SHADOW_MAP_RES` must match
  `shadowMapResolution` in `shaders.properties`.
- `gbuffers_skybasic.fsh`: `CLOUD_HEIGHT_SCALE`, `CLOUD_SPEED`,
  `CLOUD_COVERAGE`.
- `composite.fsh`: `VL_STEPS` (quality vs. cost), `VL_STRENGTH`,
  `VL_MAX_DIST`.
- `composite1.fsh`: `BLOOM_THRESHOLD`, `BLOOM_INTENSITY`, `BLOOM_RADIUS`.
- `final.fsh`: `EXPOSURE`.
- `gbuffers_water.fsh`: `SSR_STEPS`, `SSR_STEP_SIZE`.

## If something looks wrong in-game

Iris will show a compile-error screen naming the exact file/line if a shader
fails to compile - that's the fastest way to find a typo. If it compiles but
looks wrong:

- **Black/broken reflections on water** → check `depthtex1` is actually
  populated (it should be automatically; if Iris ever changes this
  convention, `gbuffers_water.fsh`'s SSR loop is where to look).
- **No colored glow through glass** → confirm `shadow.fsh`'s
  `/* RENDERTARGETS: 0 */` directive is intact; that's what routes color into
  `shadowcolor0`.
- **Clouds look stretched/wrong near the horizon** → expected at grazing
  angles from the flat-plane projection; increase the `edgeFade` range in
  `gbuffers_skybasic.fsh` if it bothers you.

## Suggested next steps

1. Test in-game across day/night/rain to confirm the deferred resolve, colored
   shadows, and volumetric shafts all behave.
2. Add a `feetPlayerPos` varying to water for self-shadowing.
3. Fold entities into the deferred G-buffer so they receive real shadows.
4. Replace the single-pass bloom with a proper downsample chain if performance
   allows.
5. Ask me for a sky-capture buffer to fix the SSR fallback, or a real
   auto-exposure buffer.
