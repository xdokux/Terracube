# UHD630-PerfShader

A minimal Iris shader pack with shadows, water reflections, and godrays,
built specifically to stay light enough for Intel UHD 630 integrated graphics.

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
