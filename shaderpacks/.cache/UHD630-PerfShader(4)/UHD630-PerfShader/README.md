# UHD630-PerfShader

A minimal Iris shader pack with shadows, water reflections, godrays, and
bloom, built specifically to stay light enough for Intel UHD 630
integrated graphics.

## v5 changelog

**Reflections rebuilt to strictly reflect the sky.** Per your request,
removed the scene ray-march entirely (that was the source of the
"buggy when reflecting other stuff" behavior - screen-space ray marching
can only ever reflect what's on-screen, so it constantly breaks down).
Water/glass now reflect a procedural sky gradient (with a sun/moon
glow) via Fresnel blending. Simpler, can't produce that class of bug,
and considerably cheaper - freed up budget for bloom below.

**Real bug found and fixed: light sources weren't giving off much
light.** The lighting formula was multiplying the *entire* lit color
(which already included block light like torches) by a factor based
only on sun angle/shadow. That meant a torch-lit room at night, with
no direct sun, could get crushed toward a ~35% brightness floor
regardless of how much torch light was actually there. Fixed by
splitting block light and sky/sun light into separate additive terms -
block light is now fully independent of sun shadow state, the way it
should be. Also gave colored stained-glass shadows a more correct
target: they now only tint the sky/sun contribution, not torchlight
on the other side of a wall from a window.

**Bloom added.** Two-pass separable blur (bright-pass + horizontal in
composite2.fsh, vertical + additive composite in composite3.fsh) -
the standard cheap technique for this. Threshold and strength are both
sliders.

**Godrays picking up moon color at night, but keeping daytime
warmth - fixed.** shadowLightPosition automatically points at the sun
by day and the moon by night, but the tint color was hardcoded warm/
orange regardless. Now compares shadowLightPosition against sunPosition
to detect day vs. night and picks a cool blue-white tint (and dimmer
overall brightness) for moonlight.

**Entity shadows not lining up with the model / jumping around /
"snapping to grid"** - I looked into this rather than guessing. This
looks like a known category of Iris engine-level issue, not something
in this pack's shader code: there's a live GitHub report of "the
player's shadow stretches out and flickers" on **Iris v1.8.8
specifically** (the exact version you're running), and Iris's own
changelog history shows its shadow culling and entity-batching system
has been rewritten before specifically to fix bugs like this. Terrain
shadows use the identical code path and aren't reported as broken,
which points at something in how Iris feeds entity vertex data into
the shadow pass specifically, rather than anything in shadow.vsh
itself.
What I'd suggest:
1. Check whether you have any of these installed, since they were
   present in the report I found: Entity Texture Features, Entity
   Model Features, Legacy4j, Legacy Skins, Physics Mod Pro, 3D Skin
   Layers, Customizable Player Model. If so, try disabling them one
   at a time.
2. Check for an Iris update newer than 1.8.8.
3. As a one-off experiment (not a real fix, just diagnostic
   information): try setting SHADOW_MAP_BIAS to 0.0 in the shader GUI.
   If the jumping changes noticeably, that tells us the distortion
   code is interacting with it and I can dig further on the shader
   side. If it looks the same, that's further evidence it's an Iris-
   level issue outside what shader code can control.
I don't want to overclaim a fix I can't verify - if you try the above
and it's still broken, it's worth reporting on the Iris GitHub issues
page, since the report I found is still open.

## New settings (in-game shader options)

SHADOW_DARKNESS, SHADOW_MAP_BIAS, SHADOW_PCF_RADIUS,
COLORED_SHADOW_STRENGTH, BLOCK_LIGHT_BRIGHTNESS, GODRAY_STRENGTH,
GODRAY_MAX_DIST, REFLECTION_STRENGTH, BLOOM_THRESHOLD, BLOOM_STRENGTH,
WATER_RIPPLE_STRENGTH, WARMTH, SATURATION, CONTRAST.

## Performance note

You mentioned 50-60fps headroom, so this version trades some of that
for bloom (2 extra full-screen passes) - but also removed the SSR ray
march entirely, which was one of the more expensive things in the
previous version. Net effect should be close to a wash, possibly a
small net gain. As always, if you drop below your target, BLOOM_STRENGTH
down or BLOOM_THRESHOLD up (fewer pixels bloom) are the cheapest things
to try first, since the blur passes' cost doesn't change with those
sliders - only GODRAY_SAMPLES (edit directly in composite1.fsh) and
SHADOW_PCF_RADIUS actually change the per-pixel workload.

## v4 changelog

**Godrays only worked facing the sun, and were grainy/too bright.**
The old version used a screen-space radial blur toward the sun's
projected screen position - that technique *can't* work off-axis, it's
not a bug that was tunable away. Replaced entirely with a raymarch
along each pixel's own view ray through the actual shadow map (same
family of technique Photon/Complementary use, simplified). This:
- Works in every view direction, not just toward the sun
- Uses interleaved gradient noise dithering instead of a cruder hash,
  which is what actually fixes the graininess (more samples alone
  wouldn't have fixed banding/noise - the noise *pattern* mattered)
- Is tightly capped (max addition ≈ GODRAY_STRENGTH × 0.35) instead of
  the previous "sky mask" hack that could still overshoot

**Shadows weren't sharp.** Added shadow map distortion (warps the
shadow map to pack far more texel density near the player, less
further away) - the same technique used by BSL/Photon/Complementary.
This is close to a free win: same resolution and render cost, sharper
result near the camera. Note: 2×2 PCF is still there for edge
smoothing, so this won't look razor-sharp like a raytraced shadow -
it'll look "defined and clean" rather than blocky/blobby. If you want
harder edges, turn SHADOW_PCF_RADIUS down toward 0.5.

**Stained glass shadows are now colored.** New feature: the shadow pass
now also writes a color buffer (`shadowcolor0`) storing the tint of
translucent casters. The main shading pass checks solid-only depth vs.
solid+translucent depth - if only translucent geometry blocks the
light, it multiplies by the stored tint instead of just darkening.
Tunable via COLORED_SHADOW_STRENGTH.

**Reflections weren't detailed.** Two real additions:
- Binary-search refinement after the coarse ray march (cheap: a few
  extra iterations) - the coarse march alone only knows a hit happened
  *somewhere* in a step's span; refinement narrows that to a precise
  intersection, which is what was actually causing the imprecise/fuzzy
  look before.
- Fresnel-based blend (more reflective at grazing angles, more
  see-through looking straight down) instead of a flat 50% blend
  regardless of angle.
- Water now has an animated, world-stable ripple normal (two cheap sine
  waves) so it isn't a perfectly flat mirror.
- Reflection fallback (when a ray finds no hit) now uses the current
  sky/fog color instead of a flat darkened tint.

## New settings (in-game shader options)

SHADOW_DARKNESS, SHADOW_MAP_BIAS, SHADOW_PCF_RADIUS,
COLORED_SHADOW_STRENGTH, GODRAY_STRENGTH, GODRAY_MAX_DIST,
REFLECTION_STRENGTH, WARMTH, SATURATION, CONTRAST.

## Honest flags for this update

- **Cost went up.** Colored shadows, the godray raymarch, and SSR
  refinement are all genuinely more expensive than the previous
  version. I can't benchmark this on your hardware from here - if you
  drop below 60fps, the two things to try first are lowering
  GODRAY_SAMPLES (edit the `#define` directly in composite1.fsh, it's
  a loop bound so it isn't a live slider) and lowering SHADOW_PCF_RADIUS.
- **SHADOW_MAP_BIAS is duplicated across 4 files** (shadow.vsh,
  gbuffers_terrain.vsh, gbuffers_water.vsh, composite1.fsh) and needs
  to match in all of them, or shadow sampling will misalign. The
  in-game slider *should* update all four together since they share
  the same macro name - this is standard Iris/OptiFine behavior, but
  I haven't tested it directly on Iris 1.8.8, so if you see the shadow
  distortion look wrong after changing that slider, let me know and
  I'll have you edit the files directly instead.
- **Godrays don't check colored glass** - only shadowtex1 (opaque-only)
  for performance reasons. So a stained-glass window will correctly
  cast a colored shadow on the ground, but a godray shaft passing
  through it won't pick up the tint. Flagging this as a scope choice,
  not an oversight - happy to add it if you want the extra cost.
- **Bias values may need retuning.** The distortion function changes
  effective texel density non-linearly across the shadow map; if you
  see shadow acne (flickering noise on lit surfaces) or peter-panning
  (shadow visibly detached from its caster), that's the next thing to
  tune (bias values are in gbuffers_terrain.fsh / gbuffers_water.fsh /
  composite1.fsh) - I can't verify the exact right value without
  seeing it running on your hardware.

## v3 changelog

## Important: turn off vanilla "Entity Shadows"

Options → Video Settings → General → **Entity Shadows: OFF**.

Minecraft has its own built-in flat gray circular shadow decal under every
entity/player, completely independent of any shaderpack. If it's still on,
you'll see it overlapping with this pack's real directional shadow — and
since the real one correctly falls off to the side based on sun angle
(not straight down), the two together read as "blobby" and "not lining up."
This is very likely the actual cause of that report - please check this
setting first.



- **Godray whiteout looking up, still happening in v2** → v2 only reduced
  (to 25%) the godray contribution on sky pixels instead of zeroing it.
  When you're looking straight up, almost the entire screen is sky, so
  that 25% was still enough to wash things out. Now fully zeroed on
  self-sky pixels.
- **Still washed out after the v2 gamma fix** → the gamma bug fix was
  correct, but this pack never had any actual color grading - it was
  just flat vanilla colors with a shadow multiplier, which reads as dull
  compared to packs like Photon or Complementary Reimagined that do
  real grading. Added a cheap warm white-balance + saturation +
  S-curve contrast pass in `final.fsh`. Tunable via the SHADOW_DARKNESS,
  GODRAY_STRENGTH, WARMTH, SATURATION, CONTRAST in-game sliders.
- **Shadows still blobby/misaligned after v2's resolution fix** → most
  likely cause is the vanilla Entity Shadows setting, see above. Also
  reduced the normal-offset bias from 0.06 to 0.02 blocks, since 0.06
  was probably enough on its own to visibly shift a small caster's
  shadow silhouette.
- Warmed the godray tint color to match the warmer atmosphere request.

## v2 changelog (fixes from earlier testing feedback)

- **Blobby player shadows** → raised shadow map to 2048 / shrank distance
  to 64 blocks (~3x denser texels), added normal-offset bias, switched
  single-tap lookup to a cheap 2x2 PCF filter.
- **Washed-out/desaturated/over-bright image** → removed an incorrect
  double gamma-correction bug in `final.fsh` (was applying Reinhard
  tonemap + pow(1/2.2) on colors that were already gamma-correct).
- **White-out looking at the sky** → not bloom (none was ever added) -
  it was an unbounded additive math bug in the godray pass that could
  push sky pixels 2-3x past white. Fixed the normalization math,
  clamped output, and reduced godray strength on pixels that are
  themselves sky.
- Reduced godray sample count 16 → 10 to help offset the shadow map
  resolution increase, aiming to keep you at/above 60fps.

## Install

1. Confirm you have Fabric Loader 0.16.14 (Java 1.21.4), Fabric API,
   Sodium 0.6.13, and Iris 1.8.8 installed.
2. Drop the `UHD630-PerfShader` folder (the one containing the `shaders`
   subfolder) into `.minecraft/shaderpacks/`.
3. In-game: Options -> Video Settings -> Shaders -> select **UHD630-PerfShader**.

## What's in it, and why it's cheap

| Feature | Technique used | Why it's cheap |
|---|---|---|
| Shadows | 1024px shadow map, single-tap lookup, no PCF blur | Cost scales with resolution²; no blur = no extra texture samples per pixel |
| Reflections | Screen-space reflection, water pixels only, 8-step fixed ray march | Non-water pixels (~95% of the screen) exit the shader immediately |
| Godrays | Screen-space radial sampling toward the sun (16 samples), reusing existing depth buffer | No separate volumetric/froxel pass, no extra render target |

Explicitly **not** included: SSAO, TAA, volumetric fog, bloom, PBR/specular
material response. These are the most common causes of sub-60fps performance
on integrated graphics, and weren't part of your request. Adding any of them
later will cost real frame time — happy to help add them if you want to trade
some performance for more visual fidelity.

## Recommended settings for 60fps on UHD 630

**Iris shader options (in-game, after selecting the pack):**
- Shadow Darkness: default (0.35) is fine; lower = cheaper-*feeling* but not
  actually cheaper (darkness doesn't change sample cost, only shadow map
  resolution and distance do).
- If you still don't hit 60fps, the first things to reduce are outside this
  pack, in Sodium/vanilla video settings (below) — the shader itself is
  already at a fairly hard floor for these three effects.

**Sodium video settings:**
- Render Distance: 8–10 chunks (biggest single lever on an iGPU)
- Simulation Distance: 6–8
- Smooth Lighting: Minimum or Off
- Entity Distance / Particles: reduced
- Vsync: off while testing (so you can see your real framerate), on for play if you get screen tearing

**Realistic expectation:** on UHD 630 specifically, 60fps with all three
effects active is achievable at moderate render distances (roughly 8–12
chunks) and at 1080p or lower. I can't guarantee 60fps at 1440p/4K or at
"Far" render distance with this or any shader pack — UHD 630 is fill-rate
and bandwidth limited, and that ceiling doesn't move regardless of how
optimized the shader code is. If you test this and it's still too slow,
the shadow map resolution (1024 → 512) is the next lever to pull, and I can
walk you through that change.

## Things I'm explicitly uncertain about (flagging per your request)

1. **Custom half-resolution buffers for SSR/godrays.** Iris supports
   rendering a colortex buffer at reduced resolution for extra performance,
   but I'm not 100% certain of the exact shaders.properties syntax for
   Iris 1.8.8 specifically (it has shifted across versions). I deliberately
   avoided guessing at it here, since getting it wrong fails silently rather
   than refusing to compile. If you want to push performance further, this
   is the next optimization to look up on the Iris GitHub wiki
   (https://github.com/IrisShaders/Iris/wiki) before adding.
2. **Shadow map caching / reduced update frequency.** Some shader packs
   only re-render the shadow map every N frames to save cost. I'm not aware
   of a simple built-in toggle for this in Iris 1.8.8, so I didn't include
   it — flagging in case you or another dev knows of one.
3. **Exact frame cost.** I can't benchmark this on your actual hardware from
   here. The design choices above are all standard, well-established
   cheap-technique choices, but real FPS numbers depend on your specific
   render distance, resolution, and what else is running on your PC.

## Want more?

Happy to help with any of the following next:
- Adding a cheap sky/cave ambient occlusion pass
- Tuning shadow bias if you see shadow acne or peter-panning
- Adding colored/underwater tinting
- A version with softer (PCF) shadows if you have headroom to spare
