vec3 get_lava_fog(float dist, vec3 color) {
    const vec3 LAVA_FOG_COLOR = to_linear(vec3(0.65, 0.35, 0.125));
    const vec3 PSNOW_FOG_COLOR = to_linear(vec3(0.5, 0.6, 0.8));

    if (isEyeInWater == 1) {
        vec3 UnderwaterCol = to_linear(vec3(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE))*(SKY_GROUND+SKY_TOP);
        UnderwaterCol = mix_preserve_c1lum(UnderwaterCol, fogColor, f_BIOME_WATER_CONTRIBUTION);
        dist = clamp(dist / 64 * UNDERWATER_FOG_STRENGTH, 0, 1);
        return mix(color, UnderwaterCol, dist);
    }
    else if (isEyeInWater == 2) {
        dist = clamp(dist / 2, 0, 1);
        return mix(color, LAVA_FOG_COLOR, dist);
    }
    else if (isEyeInWater == 3) {
        dist = clamp(dist / 2, 0, 1);
        return mix(color, PSNOW_FOG_COLOR, dist);
    }
    return color;
}

vec3 get_border_fog(float strength, vec3 color, vec3 SkyColor) {
    strength *= strength;
    #ifndef DIMENSION_NETHER
    strength *= strength;
    strength *= strength;
    #endif
    strength = min(1, (1-smoothstep(0.9, 1.5, strength)) * exp(-3 * BORDER_FOG_STRENGTH * strength));
    return mix(SkyColor, color, strength);
}

vec3 get_blindness_fog(float Dist, vec3 Color) {
    Dist = clamp(1.0 - exp(-3.0 * Dist / 10), 0, 1) * max(darknessFactor, blindness);
    return Color * (1 - Dist);
}

vec3 get_end_fog(float Dist, vec3 Color, float Depth, vec3 PlayerPos) {
    if(Dist >= furthest) {
        PlayerPos = normalize(PlayerPos) * furthest;
    }
    Dist = min(Dist / 32, 1);
    Dist = 1.0 - exp(-3.0 * Dist) + 0.0497;

    float WorldHeight = PlayerPos.y + cameraPosition.y;
    float HeightLower = 30 + max(0, -WorldHeight);
    float HeightFalloff = 1 - smoothstep(HeightLower, HeightLower + 10, WorldHeight);
    

    float Factor = Dist * HeightFalloff;
    return Color * (1 - Factor);
}

float get_shadowing(vec3 ScreenPos, vec3 LightPos, float Dither, bool IsDH) {
    if(LightPos.z > 0) return 1.0;

    vec3 LightPosScreen = view_screen(LightPos, IsDH);
    if(LightPosScreen.xy != clamp(LightPosScreen.xy, 0, 1)) return 1.0;

    // Trace
    float LightFactor = 0;
    vec3 Step = (LightPosScreen - ScreenPos) / GODRAYS_QUALITY;
    vec3 ExpectedPos = ScreenPos + Step * Dither;
    for (int i = 1; i <= GODRAYS_QUALITY; i++) {
        float RealDepth = get_depth(ExpectedPos.xy, IsDH);
        LightFactor += 1 - step(1, RealDepth);
        
        ExpectedPos += Step;
    }

    float Falloff = min_component(abs(step(0.5, LightPosScreen.xy) - LightPosScreen.xy));
    Falloff = smoothstep(0., 0.25, Falloff);

    return 1 - LightFactor / GODRAYS_QUALITY * Falloff;
}

vec3 trace_godrays(vec3 ScreenPos, float VdotL, vec3 LightPos, vec3 LightColor, float Dither, bool IsDH) {
    #ifdef GODRAYS
        float Shadowing = get_shadowing(ScreenPos, LightPos, Dither, IsDH);
    #else
        float Shadowing = 1;
    #endif

    float Phase = xlf_phase(VdotL, 0.6) * 0.66 + xlf_phase(VdotL, -0.3) * 0.33;

    return LightColor * Shadowing * Phase;
}

vec3 get_atm_fog(vec3 Color, vec3 ScreenPos, vec3 PlayerPos, float Dist, float VdotL, float Dither, bool IsDH) {
    if(fogAmount < 1e-5) return Color;
    vec3 Scattering = vec3(0);

    // Sun
    if(nightStrength < 0.99) {
        const vec3 SUN_GLARE = to_linear(vec3(0.7, 0.45, 0.0));
        vec3 SunColor = (SUN_DIRECT * dayStrength + SUN_GLARE * (sunsetStrength + sunriseStrength) * (1 - 0.33 * (rainStrength + thunderStrength)) * 4);
        Scattering += trace_godrays(ScreenPos, VdotL, sunPosN, SunColor, Dither, IsDH);
    }

    // Moon
    if(dayStrength < 0.01) {
        vec3 MoonColor = (SUN_DIRECT * nightStrength);
        Scattering += trace_godrays(ScreenPos, -VdotL, -sunPosN, MoonColor, Dither, IsDH);
    }

    // Ambient
    Scattering += SUN_AMBIENT / PI;

    // Apply other effects
    Scattering = tint_underwater(Scattering);
    Scattering *= 1 - max(darknessFactor, blindness);

    // Make sure it doesn't extend forever (it would look ugly)
    float Density = min(1, Dist / furthest);

    vec3 WorldPos = PlayerPos + cameraPosition;
    float HeightFalloff = WorldPos.y >= 50 ? smoothstep(50, 70, WorldPos.y) - smoothstep(70, 120, WorldPos.y) : 0;
    Density *= 0.33 + HeightFalloff * pow4(1 - fbm_fast(WorldPos.xz, 1)) * (1 - Density);

    Density *= fogAmount * ATM_FOG_STRENGTH;

    const float ABSORBTION = 0.5;
    // Boost with godrays to make it look cooler
    #ifdef GODRAYS
        const float SCATTERING = 2;
    #else
        const float SCATTERING = 1;
    #endif
    const float EXTINCTION = ABSORBTION + SCATTERING;

    float Transmittance = exp(-EXTINCTION * Density);

    return Color * Transmittance + Scattering * (1 - Transmittance) * SCATTERING / EXTINCTION;
}

vec3 get_fog_main(vec3 ScreenPos, vec3 PlayerPos, vec3 Color, float Depth, vec3 SkyColor, float VdotL, float Dither, bool IsDH) {
    float Dist = length(PlayerPos);
    
    if (Depth < 1) {
        #if defined BORDER_FOG && !defined CUSTOM_SKYBOXES
            Color.rgb = get_border_fog(Dist / furthest, Color.rgb, SkyColor);
        #endif
    }

    #if defined DIMENSION_OVERWORLD && defined ATMOSPHERIC_FOG
        Color.rgb = get_atm_fog(Color.rgb, ScreenPos, PlayerPos, Dist, VdotL, Dither, IsDH);
    #endif
    #ifdef DIMENSION_END
        Color.rgb = get_end_fog(Dist, Color.rgb, Depth, PlayerPos);
    #endif
    Color.rgb = get_lava_fog(Dist, Color.rgb);
    Color.rgb = get_blindness_fog(Dist, Color.rgb);
    return Color;
}
