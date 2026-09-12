vec3 getViewDir(vec2 uv) {
    vec4 clip = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return normalize(view.xyz / view.w);
}

vec3 trace_godrays(vec3 ScreenPos, vec3 LightPos, vec3 LightColor, float Dither, bool IsDH) {
    vec3 LightPosScreen = view_screen(LightPos, IsDH);
    
    // --- FIX START ---
    // 1. Define how far off-screen the sun can be before rays disappear completely.
    // 1.0 = Edge of screen, 3.0 = Far off-screen.
    float MaxDist = 1.0; 

    float Dist = distance(LightPosScreen.xy, ScreenPos.xy);
    
    // 2. Check against the new wider distance
    if (Dist > MaxDist) return vec3(0);

    // 3. Normalize the falloff so it fades smoothly over the new distance
    float Falloff = 1.0 - (Dist / MaxDist);
    // --- FIX END ---

    // Softer, dreamier falloff
    // Note: Since Falloff is now spread over a larger area, 
    // you might want to lower this power slightly (e.g. to 2.0 or 2.5) 
    // if the rays look too faint at the edges.
    LightColor *= pow(Falloff, 3.0); 
    LightColor *= 1.2;    

    LightColor *= vec3(1.05, 0.95, 0.85);

    // Trace
    vec3 Step = (LightPosScreen - ScreenPos) / GODRAYS_QUALITY;
    float Att = length(Step);
    vec3 ExpectedPos = ScreenPos + Step * Dither;
    float LightFactor = 0.0;
    
    // Safety: If the sun is WAY off screen, steps can become huge and cause lag/artifacts.
    // Optional: Clamp the step size if you experience lag when looking away.
    
    for (int i = 1; i <= GODRAYS_QUALITY; i++) {
        float RealDepth = get_depth(ExpectedPos.xy, IsDH);
        float t = float(i) / GODRAYS_QUALITY;
        float depthWeight = exp(-t * 0.3); 
        LightFactor += step(1.0, RealDepth) * depthWeight;
        
        float rayNoise = bayer8(ExpectedPos.xy * resolution + frameCounter * 0.5);
        LightFactor += step(1.0, RealDepth) * mix(0.85, 1.15, rayNoise);
        
        float visibility = smoothstep(0.98, 1.0, RealDepth);
        LightFactor += visibility;
        ExpectedPos += Step;
    }
    
    const float SettingsFactor = (1.0 / GODRAYS_QUALITY) * GODRAYS_STRENGTH * 1.3;
    return LightColor * LightFactor * SettingsFactor;
}

vec3 godrays(vec3 ScreenPos, float Dither, bool IsDH) {
    vec3 Scattering;
    if (sunPosN.z < 0) {
        const vec3 SUN_GLARE = to_linear(vec3(0.7, 0.45, 0.0));
        vec3 SunColor = (SUN_DIRECT * dayStrength / 4 + SUN_GLARE * (sunsetStrength + sunriseStrength) * (1 - 0.33 * (rainStrength + thunderStrength)));
        Scattering = trace_godrays(ScreenPos, sunPosN, SunColor, Dither, IsDH);
    }
    else { // Moon
        vec3 MoonColor = vec3(0.820, 0.761, 0.647);
        Scattering = trace_godrays(ScreenPos, -sunPosN, MoonColor / 24, Dither, IsDH);
    }

     // === World-space ambient scattering (NEW)
    float height = max(0.0, cameraPosition.y - 62.0);
    float airDensity = exp(-height * 0.02);

    vec3 sunDir = normalize(sunPosN);
    vec3 viewDir = getViewDir(ScreenPos.xy);

    float sunAmount =
        clamp(dot(viewDir, sunDir) * 0.5 + 0.5, 0.0, 1.0);

    vec3 worldScattering =
        SUN_DIRECT
        * sunAmount
        * airDensity
        * 0.03;

    // Blend it softly
    Scattering += worldScattering;

    Scattering = tint_underwater(Scattering);
    Scattering *= 1 - max(darknessFactor, blindness);
    Scattering *= 1 + (-rainStrength-thunderStrength)/2;

    return Scattering;
}

