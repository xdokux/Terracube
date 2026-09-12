vec3 trace_godrays(vec3 ScreenPos, vec3 LightPos, vec3 LightColor, bool IsDH) {
    vec3 LightPosScreen = view_screen(LightPos, IsDH);
    float Falloff = distance(LightPosScreen.xy, ScreenPos.xy);
    if (Falloff > 1) return vec3(0);
    Falloff = 1 - Falloff;

    // Smoother falloff curve for more natural god rays
    LightColor *= pow(Falloff, 3.0) * Falloff;

    // Trace
    vec3 Step = (ScreenPos - LightPosScreen) / GODRAYS_QUALITY;
    float Noise = dither(gl_FragCoord.xy);
    vec3 ExpectedPos = LightPosScreen + Step * Noise;
    float LightFactor = 0;
    for (int i = 1; i <= GODRAYS_QUALITY; i++) {
        float RealDepth;
        if (isEyeInWater == 1) {
            RealDepth = get_depth_solid(ExpectedPos.xy, IsDH);
        }
        else {
            RealDepth = get_depth(ExpectedPos.xy, IsDH);
        }

        if (RealDepth == 1) {
            // Weight samples closer to the light more heavily
            float Weight = 1.0 - float(i) / float(GODRAYS_QUALITY) * 0.3;
            LightFactor += Weight;
        }
        ExpectedPos += Step;
    }
    const float SettingsFactor = 1.0 / GODRAYS_QUALITY * GODRAYS_STRENGTH;
    return LightColor * LightFactor * SettingsFactor;
}

vec3 godrays(vec3 ScreenPos, bool IsDH) {
    vec3 Scattering;
    if (sunPosN.z < 0) {
        const vec3 SUN_GLARE = to_linear(vec3(0.8, 0.48, 0.0));
        vec3 SunColor = (SUN_DIRECT * dayStrength / 4 + SUN_GLARE * (sunsetStrength + sunriseStrength));
        Scattering = trace_godrays(ScreenPos, sunPosN, SunColor, IsDH);
    }
    else { // Moon
        vec3 MoonColor = (SUN_DIRECT * nightStrength / 3);
        Scattering = trace_godrays(ScreenPos, -sunPosN, MoonColor, IsDH);
    }
    Scattering = tint_underwater(Scattering);
    Scattering *= 1 - max(darknessFactor, blindness);

    return Scattering;
}
