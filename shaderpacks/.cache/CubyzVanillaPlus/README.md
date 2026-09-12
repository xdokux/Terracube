# CubyzVanillaPlus (v1)

A from-scratch vanilla-plus shaderpack for Cubyz's irisbridge: real shadow
maps, animated water with a sun-glint specular, per-stage fog, and a
whole-screen tonemap/contrast/vignette pass.

## What's implemented
- `shadow.vsh/fsh` - basic orthographic shadow map (no distortion/PCSS yet)
- `gbuffers_terrain.vsh/fsh` - shadow-mapped diffuse lighting blended with
  Cubyz's own per-vertex torch/sky light, plus distance fog from `cubyz_Fog`
- `gbuffers_water.vsh/fsh` - animated wave displacement on fluid top faces,
  shadow-aware specular sun glint, same fog treatment as terrain
- `composite.vsh/fsh` - Reinhard tonemap, contrast/saturation lift, vignette
- `final.vsh/fsh` - straight present of composite's output

## What's deliberately left out of v1
- Normal maps / parallax (no LabPBR normal data to drive them anyway)
- Shadow distortion (shadow resolution is uniform across distance - fine at
  short range, will look soft far from the player)
- A dedicated sky shader - Cubyz's own sky renders as-is since we don't ship
  `gbuffers_skybasic`
- Any in-game option toggles - constants are hardcoded at the top of
  `composite.fsh` for now

## First things to check after loading
This was written from four confirmed-working example shaders plus one
that failed to compile (from testing other packs) - not from the bridge's
own source, so there's real risk a uniform/attribute name is subtly wrong.
After loading, check the log for:
1. Any `OpenGL Shader Compiler error` lines - if `gbuffers_terrain` or
   `gbuffers_water` fail, the fragment shader falls back silently and you'll
   see Cubyz's default shading instead, not a crash.
2. `irisbridge: shadow program did not compile; shadows stay unoccluded` -
   if you see this, shadows are being skipped rather than broken; the rest
   of the pack still works, just flat-lit.
3. `reads N uniform(s) nothing supplies, so they are zero` - if
   `shadowLightPosition`, `cubyz_ambientLight`, or the shadow matrices show
   up here, the lighting math will be wrong even though it compiles.

If you hit any of the above, send me the fresh log and I'll fix it the same
way we fixed LIGHT-Shaders.
