# UHD630Shader

A minimal Iris shader pack built for **Fabric 0.16.14, Minecraft 1.21.4, Sodium 0.6.13, Iris 1.8.8**,
targeting weak integrated graphics (Intel UHD 630). Provides:
- Directional sun/moon shadows (single non-cascaded shadow map)
- Screen-space godrays (cheap 2D radial-sample technique, not true volumetrics)
- Screen-space reflections on water only

## Installation
1. Confirm Fabric Loader 0.16.14 + Fabric API + Sodium 0.6.13 + Iris 1.8.8 are installed and Minecraft launches to the main menu without errors first.
2. Copy the `UHD630Shader` folder into `.minecraft/shaderpacks/` (create that folder if it doesn't exist).
3. In-game: Options → Video Settings → Shaders → select `UHD630Shader`.
4. Open the shader's own options screen (button next to the shader list) to adjust `SSR_STEPS`, `SSR_MAX_DIST`, and `GODRAY_SAMPLES`, or just pick the `LOW` profile if you haven't already (it's the default).

## Performance tuning order (do these in order if FPS is too low)
1. Lower `shadowMapResolution` in `shader.properties` from 1024 to 512.
2. Drop `GODRAY_SAMPLES` to 4 (already default) — this is one of the cheaper effects here, so this alone won't save much.
3. Drop `SSR_STEPS` to 6 (already default), or disable SSR entirely by commenting out the reflection block in `composite1.fsh` if you have almost no visible water in your builds.
4. In Iris's video settings, lower **Shadow Distance** — this is a runtime slider Iris controls, not something set in this pack, but it's usually the single biggest shadow-pass cost.
5. As a last resort, disable shadows entirely in Iris's shader options (Iris exposes a global shadow toggle even if the pack doesn't define one).

## Known limitations / things I'm explicitly uncertain about
Being upfront about these rather than hiding them, since you said this will get expert review:

- **No colored/translucent shadows.** Stained glass and colored blocks cast solid opaque shadows. Adding colored shadows needs a second shadow color buffer (`shadowcolor0`) and roughly doubles shadow-pass sampling cost — I left it out on purpose for UHD 630.
- **Godrays are a 2D screen-space approximation**, not real volumetric light shafts. They only look correct when the sun/moon is on-screen or near it; they will not produce shafts of light streaming through a window from an off-screen sun the way Photon's volumetric fog does. This was the single biggest cost-vs-fidelity trade in the whole pack.
- **SSR is a minimal reference implementation.** No binary-search refinement, no roughness blur, no sky-color fallback on ray miss. Expect visible stepping on reflections at the default 6 steps. I have not compiled or run this in-game myself — treat the raymarch hit-test logic (`composite1.fsh`) as a starting point that will likely need sign/threshold tuning once you see it rendering, which is normal even for experienced shader devs writing SSR from scratch.
- **Only terrain and water are covered.** Sky, clouds, entities, hand, and particles all fall back to Iris's internal default rendering, since I didn't write `gbuffers_entities`, `gbuffers_sky`, etc. This is a deliberate scope-reduction for performance (fewer shader programs = faster compile + fewer buffer writes) and is a normal thing for lightweight packs to do, but it does mean entities won't cast/receive the same shadow treatment as terrain, and reflections won't show entities standing near water.
- **`shadowLightPosition`, `sunPosition`, `gbufferModelViewInverse`, etc. are Iris/OptiFine-standard uniforms** documented at the Iris shader development docs (see below) — I'm using them per that spec, but I'd recommend double-checking against the live docs since uniform behavior has occasionally shifted across Iris versions.

## Reference material worth pulling up alongside this
- Iris shader development docs: https://shaders.properties/ (community-maintained but the closest thing to an authoritative Iris/OptiFine shader spec)
- Iris source/issues for uniform behavior questions: https://github.com/IrisShaders/Iris
- For studying more advanced versions of these same techniques: Complementary Reimagined, Photon, Solas, and BSL are all open-source — reading their `composite*.fsh` files is the fastest way to see how they handle cascaded shadows, volumetric fog, and roughness-aware SSR once you want to grow beyond this baseline.

## Suggested next steps if you want to extend this
- Ask me for a **cascaded shadow variant** once base performance is confirmed acceptable.
- Ask me for a **sky/fog pass** (`gbuffers_skybasic` + a fog blend in composite) to make godrays look correct even when the sun isn't directly on-screen.
- Ask me for **PBR-lite specular highlights** on water using a fixed light direction, which is much cheaper than full SSR and could replace it if SSR proves too slow.
