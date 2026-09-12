// ============================================================
//  CinematicVanilla V2 - dynamicLighting.glsl   (NEW)
//  Day/night light color transitions + soft GI approximation.
//  Include in complexShadingDeferred.glsl or world.glsl.
// ============================================================

// ─── Dynamic Light Color by Time of Day ─────────────────────────────────────
// Returns the sun/moon light color tinted for cinematic looks:
//   Dawn/Dusk  → warm amber-orange
//   Midday     → cool white-blue
//   Night      → cool blue-violet moonlight
vec3 getDynamicLightColor(in vec3 sunCol, in vec3 moonCol){
    #ifndef FORCE_DISABLE_DAY_CYCLE
        // dayCycleAdjust: 0=night, ~0.5=twilight, 1=midday
        float t  = dayCycleAdjust;
        float tw = 1.0 - abs(t * 2.0 - 1.0);  // peaks at 0.5 (twilight)
        tw *= tw;

        // Sunrise/sunset warm push — amber tint on sun light
        vec3 warmTwilightSun = sunCol * vec3(1.25, 0.90, 0.60);
        // Midday: slight cool-white push (high atmosphere scattering)
        vec3 middaySun       = sunCol * vec3(0.95, 0.98, 1.08);
        // Blend based on twilight factor
        vec3 dynSun = mix(middaySun, warmTwilightSun, tw);

        // Night: blue-violet moonlight
        vec3 dynMoon = moonCol * vec3(0.75, 0.82, 1.15);

        return mix(dynMoon, dynSun, t);
    #else
        return sunCol;
    #endif
}

// ─── Soft GI Approximation ──────────────────────────────────────────────────
// Very cheap: adds a small amount of sky color as a bounced indirect
// contribution scaled by the surface's upward normal component and lightmap.
// Mimics light bouncing off the ground/sky into shaded surfaces.
// normal: world-space surface normal
// skyCol: current sky color (linear)
// lightmapSky: the Y component of the lightmap (0..1)
vec3 getSoftGI(in vec3 normal, in vec3 skyCol, in float lightmapSky){
    // Upward-facing surfaces receive sky GI
    float upFacing = saturate(normal.y * 0.5 + 0.5);
    // Downward-facing surfaces get a faint ground bounce (brown-grey)
    float downFacing = saturate(-normal.y * 0.5 + 0.5);
    const vec3 groundBounce = vec3(0.12, 0.10, 0.07);

    vec3 gi = skyCol * upFacing * lightmapSky * 0.08
            + groundBounce * downFacing * lightmapSky * 0.04;
    return gi;
}
