vec3 get_lava_fog_fast(float dist, vec3 color) {
    if (isEyeInWater == 0) return color;
    const vec3 LAVA_FOG = vec3(0.4225, 0.1225, 0.015625);
    const vec3 PSNOW_FOG = vec3(0.25, 0.36, 0.64);
    if (dist > 100.0) return color;
    if (isEyeInWater == 1) {
        vec3 UnderwaterCol;
        #ifdef DIMENSION_OVERWORLD
        UnderwaterCol = vec3(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE);
        #elif defined DIMENSION_END
        UnderwaterCol = vec3(0.05, 0.02, 0.08);
        #else
        UnderwaterCol = vec3(0.1, 0.02, 0.02);
        #endif
        UnderwaterCol *= UnderwaterCol * (SKY_GROUND + SKY_TOP);
        float t = clamp(dist * (1.0/64.0), 0.0, 1.0);
        return mix(color, UnderwaterCol, t);
    }
    float t = clamp(dist * 0.5, 0.0, 1.0);
    vec3 fogCol = (isEyeInWater == 2) ? LAVA_FOG : PSNOW_FOG;
    return mix(color, fogCol, t);
}
vec3 get_border_fog_fast(float strength, vec3 color, vec3 SkyColor) {
    if (strength < 0.001) return color;
    #ifdef DIMENSION_NETHER
    strength = clamp(strength * strength, 0.0, 1.0);
    #else
    strength = clamp(strength * strength * strength * strength, 0.0, 1.0);
    #endif
    float factor = exp(-3.0 * strength);
    return mix(SkyColor, color, factor);
}
vec3 get_blindness_fog_fast(float Dist, vec3 Color) {
    float darkness = max(darknessFactor, blindness);
    if (darkness < 0.001) return Color;
    if (Dist > 200.0) return Color * (1.0 - darkness);
    float factor = clamp(1.0 - exp(-0.3 * Dist), 0.0, 1.0) * darkness;
    return Color * (1.0 - factor);
}
vec3 get_end_fog_fast(float Dist, vec3 Color, vec3 PlayerPos) {
    if (Dist > 500.0) return vec3(0.0005);
    if (Dist >= furthest) {
        PlayerPos = normalize(PlayerPos) * furthest;
    }
    float t = min(Dist * (1.0/32.0), 1.0);
    t = 1.0 - exp(-3.0 * t) + 0.0497;
    float WorldHeight = PlayerPos.y + cameraPosition.y;
    float HeightLower = 30.0 + max(0.0, -WorldHeight);
    float HeightFalloff = 1.0 - smoothstep(HeightLower, HeightLower + 10.0, WorldHeight);
    float Factor = t * HeightFalloff;
    return mix(Color, vec3(0.0005), Factor);
}
vec3 get_atm_fog_fast(vec3 Color, vec3 PlayerPos, float Dist, float VdotL) {
    if (fogAmount < 1e-5) return Color;
    if (Dist > 500.0) return Color * 0.1;
    vec3 Scattering = SUN_AMBIENT * (0.5 / PI);
    Scattering *= 1.0 - max(darknessFactor, blindness);
    float Density = min(1.0, Dist / furthest);
    vec3 WorldPos = PlayerPos + cameraPosition;
    float HeightFalloff = (WorldPos.y >= 50.0)
    ? smoothstep(50.0, 70.0, WorldPos.y) - smoothstep(70.0, 120.0, WorldPos.y)
    : 0.0;
    Density *= (0.33 + HeightFalloff * 0.5) * fogAmount;
    const float EXTINCTION = 1.5;
    float Transmittance = exp(-EXTINCTION * Density);
    return Color * Transmittance + Scattering * (1.0 - Transmittance);
}
vec3 get_fog_main(vec3 ScreenPos, vec3 PlayerPos, vec3 Color, float Depth, vec3 SkyColor, float VdotL, float Dither, bool IsDH) {
    float Dist = length(PlayerPos);
    if (Dist > 1000.0) return Color;
    #if defined BORDER_FOG && !defined CUSTOM_SKYBOXES
    if (Depth < 1.0) {
        Color = get_border_fog_fast(Dist / furthest, Color, SkyColor);
    }
    #endif
    #if defined DIMENSION_OVERWORLD && defined ATMOSPHERIC_FOG
    Color = get_atm_fog_fast(Color, PlayerPos, Dist, VdotL);
    #endif
    #ifdef DIMENSION_END
    Color = get_end_fog_fast(Dist, Color, PlayerPos);
    #endif
    Color = get_lava_fog_fast(Dist, Color);
    Color = get_blindness_fog_fast(Dist, Color);
    return Color;
}
