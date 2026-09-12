// ============================================================
//  CinematicVanilla V2 - fogRender.glsl
//  Cinematic fog: height + distance, day/night density,
//  sunset/dawn warm tint, rain boost, god-ray interaction.
// ============================================================

// ─── Border Fog ─────────────────────────────────────────────────────────────
float getBorderFog(in float playerPosLength){
    return exp2(-exp2(playerPosLength / borderFar * 21.0 - 18.0));
}

// ─── Height Fog (exponential) ────────────────────────────────────────────────
float getAtmosphericFog(in float nPlayerPosY, in float worldPosY,
                        in float playerPosLength,
                        in float totalDensity, in float verticalFogDensity){
    return (totalDensity / verticalFogDensity)
         * exp2(-worldPosY * verticalFogDensity)
         * (1.0 - exp2(-playerPosLength * nPlayerPosY * verticalFogDensity))
         / nPlayerPosY;
}

float getFogFactor(in float viewDist, in float nEyePlayerPosY, in float worldPosY){
#ifdef CINEMATIC_FOG
    // Density scales with rain and is slightly denser at night
    #ifdef FORCE_DISABLE_WEATHER
        float vFogDens   = isEyeInWater == 0 ? FOG_VERTICAL_DENSITY : FOG_VERTICAL_DENSITY * 0.2;
        float totalDens  = isEyeInWater == 0 ? FOG_TOTAL_DENSITY    : FOG_TOTAL_DENSITY * TAU;
    #else
        float rainBoost  = rainStrength * eyeBrightFact;
        float vFogDens   = isEyeInWater == 0
                         ? FOG_VERTICAL_DENSITY - FOG_VERTICAL_DENSITY * rainStrength * 0.8
                         : FOG_VERTICAL_DENSITY * 0.2;
        float totalDens  = isEyeInWater == 0
                         ? FOG_TOTAL_DENSITY * (rainBoost * PI + 1.0)
                         : FOG_TOTAL_DENSITY * TAU;
    #endif

    // Night: very slightly denser ground fog (moon mist)
    #if defined WORLD_LIGHT && !defined FORCE_DISABLE_DAY_CYCLE
        float nightBoost = saturate(1.0 - dayCycleAdjust * 2.0) * 0.25;
        vFogDens  += nightBoost * FOG_VERTICAL_DENSITY;
        totalDens += nightBoost * FOG_TOTAL_DENSITY;
    #endif

    return min(1.0, getAtmosphericFog(nEyePlayerPosY, max(0.0, worldPosY),
               viewDist, totalDens, vFogDens))
         * min(1.0, GROUND_FOG_STRENGTH + GROUND_FOG_STRENGTH * isEyeInWater);
#else
    return 0.0; // Cinematic fog toggled off
#endif
}

float getFogEffectFactor(in float viewDist){
    return exp2(-viewDist * effectFactor);
}

// ─── Fog Color Tint ─────────────────────────────────────────────────────────
// Warm orange at sunrise/sunset, cool blue at night, neutral at noon.
vec3 getFogTint(){
#if defined WORLD_LIGHT && !defined FORCE_DISABLE_DAY_CYCLE && defined CINEMATIC_FOG
    float tw = 1.0 - abs(dayCycleAdjust * 2.0 - 1.0);
    tw = tw * tw;
    float night = saturate(1.0 - dayCycleAdjust * 2.0);

    vec3 twilightTint = vec3(1.14, 0.86, 0.70);  // warm orange
    vec3 nightTint    = vec3(0.80, 0.88, 1.12);  // cool blue-violet
    vec3 dayTint      = vec3(1.00, 1.00, 1.00);

    vec3 tint = mix(dayTint, twilightTint, tw);
    tint = mix(tint, nightTint, night * (1.0 - tw));
    return tint;
#else
    return vec3(1.0);
#endif
}

// ─── God Ray Factor ─────────────────────────────────────────────────────────
// Returns an additive brightness contribution from volumetric sun shafts.
// Sampled as a cheap radial raymarch toward the projected sun position.
// Expects: screenUV (texCoord), colortex for shadow map.
#ifdef GOD_RAYS
float getGodRayFactor(in vec2 uv, in vec3 lightScreenPos){
    if(lightScreenPos.z < 0.0) return 0.0; // Sun behind camera

    vec2 dir   = (lightScreenPos.xy - uv) / float(GOD_RAY_STEPS);
    vec2 sUV   = uv;
    float accum = 0.0;

    for(int i = 0; i < GOD_RAY_STEPS; i++){
        sUV += dir;
        float shadow = texture(depthtex0, sUV).r; // 1=sky, <1=geometry
        accum += shadow > 0.9999 ? 1.0 : 0.0;
    }
    float raw  = accum / float(GOD_RAY_STEPS);
    float dist = length(lightScreenPos.xy - uv);
    // Attenuate away from sun, clamp to reasonable maximum
    return raw * GOD_RAY_STRENGTH * exp(-dist * 2.5);
}
#endif
