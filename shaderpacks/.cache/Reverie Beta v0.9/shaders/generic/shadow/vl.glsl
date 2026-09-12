#ifndef DIMENSION_OVERWORLD
mat2x3 nether_fog(vec3 StartPos, vec3 EndPos, vec3 PlayerPosN, vec3 ScreenPos, float Dither, const int STEP_COUNT, const bool DoRT) {
    vec3 WorldPos = cameraPosition + StartPos;

    #ifdef DIMENSION_NETHER
        const vec3 SCATTERING = vec3(0);
        const vec3 ABSORBTION = vec3(1);
        const float DENSITY = 0.05;
        const float MAX_HEIGHT = 120.0;
    #else
        const vec3 SCATTERING = vec3(0.05, 0.2, 0.4);
        const vec3 ABSORBTION = vec3(0.2, 0.45, 1.0) * 0.2;
        const float DENSITY = 0.25;
         const float MAX_HEIGHT = 200.0;
    #endif

   

    vec3 AmbientColor = vec3(0);
    vec3 DirectColor = get_direct_color(false, cameraPosition.y * 5);

    const vec3 EXTINCTION = SCATTERING + ABSORBTION;

    if(!ray_intersect(WorldPos, StartPos, EndPos, PlayerPosN, MAX_HEIGHT)) mat2x3(vec3(0), vec3(1));

    if(length(EndPos) > farLod) {
        float StartPosL = length(StartPos);
        EndPos = StartPos + PlayerPosN * (farLod - StartPosL);
    }

    float StepCount = adaptive_samples(STEP_COUNT, PlayerPosN.y);

    vec3 Step = (EndPos - StartPos) / StepCount;
    float StepSize = length(Step);
    vec3 TotalTransmittance = vec3(1);
    vec3 TotalScattering = vec3(0);
    vec3 PlayerPosC = StartPos + Dither * Step;

    float VdotL = dot(view_player(sLightPosN, false), PlayerPosN);
    float MiePhase = cs_phase(VdotL, anisotropy * 0.4) * 0.75 + cs_phase(VdotL, -anisotropy * 0.3) * 0.25;

    float DensityConstant = DENSITY * StepSize;

    for (int i = 1; i <= StepCount; i++) {
        vec3 WorldPosC = PlayerPosC + cameraPosition;

        float Density = noise_smoke(WorldPosC);
        Density *= height_falloff(WorldPosC.y, MAX_HEIGHT);
        Density *= DensityConstant;
        if (Density <= 0) {
            PlayerPosC += Step;
            continue;
        }

        vec3 Transmittance = vec3(exp(-Density * EXTINCTION));
        vec3 T = TotalTransmittance;
        vec3 ScatteringSample = AmbientColor * T;

        vec3 ShadowNDCPosC = player_shadow(PlayerPosC);
        vec3 ShadowPosC = distort(ShadowNDCPosC);
        ShadowPosC = ShadowPosC * 0.5 + 0.5;
        float ShadowFactor = get_shadow_unfiltered(PlayerPosC, ShadowPosC);

        ScatteringSample += DirectColor * T * MiePhase * ShadowFactor;

        TotalScattering += TotalTransmittance * ScatteringSample * (1 - Transmittance) * SCATTERING / EXTINCTION;

        TotalTransmittance *= Transmittance;
        PlayerPosC += Step;
    }

    return mat2x3(TotalScattering, TotalTransmittance);
}
#endif

float get_vl_shadowing(vec3 ScreenPos, vec3 LightPos, float Dither, bool IsDH, const bool OutsideShadowDist) {
    if(LightPos.z > 0) return 0.5;

    vec3 LightPosScreen = view_screen(LightPos, IsDH, true);
    if(LightPosScreen.xy != clamp(LightPosScreen.xy, 0, 1)) return 0.5;

    // Trace
    float LightFactor = 0;
    vec3 Step = (LightPosScreen - ScreenPos) / 8;
    vec3 ExpectedPos = ScreenPos + Step * Dither;
    for (int i = 1; i <= 8; i++) {
        float RealDepth = get_depth_solid(ExpectedPos.xy, IsDH);
        if(OutsideShadowDist) {
            float RealDepthL = length(screen_view(vec3(ScreenPos.xy, RealDepth), IsDH, true));
            RealDepth = RealDepthL < shadowDistanceDH - 16 ? 1 : RealDepth;
        }
        LightFactor += step(1, RealDepth);
        
        ExpectedPos += Step;
    }

    float Falloff = min_component(abs(step(0.5, LightPosScreen.xy) - LightPosScreen.xy));
    Falloff = smoothstep(0., 0.25, Falloff);

    return mix(0.5, LightFactor / 8, Falloff);
}


mat2x3 do_water_vl(vec3 StartPos, vec3 EndPos, vec3 PlayerPosN, float Dither, vec3 LightColorDirect, vec3 ScreenPos, bool IsDH, const int STEP_COUNT, const bool DoRT) {
    const vec3 WATER_ABSORBTION = WaterAbsorbtion;
    const vec3 WATER_SCATTERING = WaterColor;
    const float SIGMA_WATER = 1;
    const vec3 WATER_EXTINCTION = SIGMA_WATER * (WATER_ABSORBTION + WATER_SCATTERING);

    vec3 WorldPos = cameraPosition + StartPos;
    
    vec3 Step = (EndPos - StartPos) / STEP_COUNT;
    float StepSize = length(Step);

    vec3 PlayerPosC = StartPos + Dither * Step;

    vec3 AmbientColor = dataBuf.AmbientColor;

    AmbientColor = mix(MinLight, AmbientColor, isOutdoorsSmooth);
    float VdotL = dot(view_player(sLightPosN, false), PlayerPosN);

    float Density = StepSize;
    vec3 TotalScattering = vec3(0);
    vec3 TotalTransmittance = vec3(1), Transmittance;

    float SunPhase = cs_phase(VdotL, 0.8);

    vec3 fms = WATER_SCATTERING / WATER_EXTINCTION * (1 - exp(-1 * WATER_EXTINCTION));
    vec3 MS = ISOTROPIC_PHASE * fms / (1 - fms);

    float CloudShadow = cloud_shadows(StartPos + cameraPosition);

    if(!DoRT) {
        float Shadow = eyeBrightnessSmooth.y / 240.0 * CloudShadow;
        if(isEyeInWater == 1)
            Shadow *= get_vl_shadowing(ScreenPos, sLightPosN, Dither, IsDH, false);
        if(isEyeInWater == 0)
            Shadow = texture(colortex5, ScreenPos.xy).r;


        TotalTransmittance = exp(-Density * WATER_EXTINCTION * STEP_COUNT);
        Transmittance = TotalTransmittance;

        float DistToSky = 5;
        float DistToSun = DistToSky / max(0.0001, view_player(sLightPosN, false).y);
        vec3 SkyAttenuation = exp(-DistToSky * WATER_EXTINCTION);
        vec3 SunAttenuation = exp(-DistToSun * WATER_EXTINCTION);

        TotalScattering = AmbientColor * ISOTROPIC_PHASE * SkyAttenuation + LightColorDirect * (SunPhase + MS) * Shadow * SunAttenuation;
    } else {
        Transmittance = exp(-Density * WATER_EXTINCTION);

        for (int i = 1; i <= STEP_COUNT; i++) {
            vec3 WorldPosC = PlayerPosC + cameraPosition;

            float DistToSky = 5;
            vec3 SkyAttenuation = exp(-DistToSky * WATER_EXTINCTION);
            TotalScattering += TotalTransmittance * AmbientColor * SkyAttenuation * ISOTROPIC_PHASE;

            vec3 ShadowNDCPosC = player_shadow(PlayerPosC);
            vec3 ShadowPosC = distort(ShadowNDCPosC);
            ShadowPosC = ShadowPosC * 0.5 + 0.5;
            float ShadowFactor = get_shadow_unfiltered(PlayerPosC, ShadowPosC) * CloudShadow;

            if (ShadowFactor > 0.01) { // Is in sun
                float DistToSun = DistToSky / max(0.0001, view_player(sLightPosN, false).y);
                vec3 SunAttenuation = exp(-DistToSun * WATER_EXTINCTION);
                TotalScattering += TotalTransmittance * LightColorDirect * SunAttenuation * (SunPhase + MS) * ShadowFactor;
            }

            PlayerPosC += Step;
            TotalTransmittance *= Transmittance;
        }
        
    }  
    TotalScattering *= (WATER_SCATTERING / WATER_EXTINCTION) * (1 - Transmittance);

    return mat2x3(TotalScattering, TotalTransmittance);
}

mat2x3 aerial_prespective_ld(vec3 StartPos, vec3 EndPos, vec3 ScreenPos, vec3 PlayerPosN, float Dither, float Depth, const bool ScreenspaceFallback, bool IsDH) {
    vec3 WorldPos = cameraPosition + StartPos;
    if(!ray_intersect(WorldPos, StartPos, EndPos, PlayerPosN, CLOUD_UPPER_PLANE)) return mat2x3(vec3(0), vec3(1));

    vec3 Step = (EndPos - StartPos);
    float StepSize = min(farLod, length(Step));
    if(StepSize < 1) return mat2x3(vec3(0), vec3(1));

    vec3 PlayerPosC = EndPos;

    float VdotL = dot(view_player(sLightPosN, false), PlayerPosN);

    float RayPhase = rayleigh_phase(VdotL);
    float MiePhase = cs_phase(VdotL, anisotropy);

    vec3 EarthPosC = PlayerPosC + vec3(0, cameraPosition.y * 5, 0);

    float Len = length(EarthPosC);
    vec3 OpticalDepth = all_densities(Len) * StepSize * VL_OVERWORLD_STRENGTH;

    // Fog gets strong at morning
    float DaytimeFactor = worldTime > 12000 ? smoothstep(20000, 24000, worldTime) : 1 - smoothstep(0, 2000, worldTime);
    DaytimeFactor = max(DaytimeFactor, 0.33);
    float DensityConstant = DaytimeFactor * StepSize * 2500;

    // No smoke-like ground fog :(
    float Density = 0.25 * DensityConstant;
    #ifdef DISTANT_HORIZONS
        float Height = Depth >= 1 ? (PlayerPosC.y / StepSize + 1.7) * 50 : PlayerPosC.y + cameraPosition.y;
    #else
        float Height = Depth >= 1 ? (PlayerPosC.y / StepSize + 1.) * 50 : PlayerPosC.y + cameraPosition.y;
    #endif
    Density *= height_falloff(Height, 130);
    OpticalDepth.y += Density;
    
    vec3 RayScattering = BETA_R * OpticalDepth.x;
    float MieScattering = BETA_M * OpticalDepth.y;

    vec3 MediumScattering = RayScattering + MieScattering;
    vec3 MediumExtinction = OpticalDepth.x * BETA_R_E + OpticalDepth.y * BETA_M_E;
    
    vec3 ScatteringSample = calc_scatt_towards_sun(EarthPosC + vec3(0, EarthRad, 0), view_player(sLightPosN, false), Len, vec2(RayPhase, MiePhase), RayScattering, MieScattering) * get_shadowlight_color();

    float u = view_player(sunPosN, false).y * 0.5 + 0.5;
    float v = (EarthPosC.y) / (AtmRad - EarthRad);
    vec3 MS = texture(atm_multi_scattering_sampler, vec2(u, v)).rgb * MediumScattering;

    // Cloud coverage avg
    float Shadowing = eyeBrightnessSmooth.y / 240.0;
    #ifdef CLOUDS
        Shadowing *= 1-exp2(1-cloudCoverageVl);
    #endif
    if(StartPos != vec3(0)) {
        Shadowing *= texture(colortex5, ScreenPos.xy).r; // Sample shadowmap at start position when doing vl in reflections
    }
    if(ScreenspaceFallback) {
        if(Shadowing > 1e-3) {
            Shadowing *= get_vl_shadowing(ScreenPos, sLightPosN, dither(ScreenPos.xy * resolution, true), IsDH, false);
        }
    }

    vec3 Transmittance = exp(-MediumExtinction);
    vec3 Scattering = (ScatteringSample * Shadowing + MS * isOutdoorsSmooth) * (1 - Transmittance) / MediumExtinction;

    return mat2x3(Scattering, Transmittance);
}

mat2x3 do_vl(vec3 StartPos, vec3 EndPos, vec3 PlayerPosN, vec3 ScreenPos, float Dither, vec3 LightColorDirect, bool IsDH, const int STEP_COUNT, const bool DoRT, const bool DoRTWater) {
    switch(isEyeInWater) {
        case 0:
            #ifdef DIMENSION_OVERWORLD
                if(!DoRT) {
                    return aerial_prespective_ld(StartPos, EndPos, ScreenPos, PlayerPosN, Dither, ScreenPos.z, true, IsDH);
                }
                break;
            #else
                return nether_fog(StartPos, EndPos, PlayerPosN, ScreenPos, Dither, STEP_COUNT * 3, DoRT);
            #endif
        case 1:
            return do_water_vl(StartPos, EndPos, PlayerPosN, Dither, LightColorDirect, ScreenPos, IsDH, STEP_COUNT * 2, DoRTWater);
    }
    return mat2x3(vec3(0), vec3(1));
}
