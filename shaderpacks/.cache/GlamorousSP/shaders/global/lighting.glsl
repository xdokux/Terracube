// Never include this file directly. Use gbuffers.fsh/vsh instead

vec2 tweak_lightmap_vertex(vec2 LightmapCoords, inout vec3 SunAmbient, vec3 ViewPosN, vec3 PlayerPos) {
    LightmapCoords = max(LightmapCoords * 1.06667 - 0.0625, 0);

    LightmapCoords.x = pow(LightmapCoords.x, 4.0001 - LM_FALLOFF_CURVE);

    #ifdef DIMENSION_OVERWORLD
        // Make ambient lighting a little brighter to match the sky
        float NdotU = clamp(dot(gbufferModelView[1].xyz, TBN[2]), -1, 1);
        vec3 SkyGround = SKY_GROUND + get_sun_glare(clamp(dot(TBN[2], sunPosN), -1, 1));
        SunAmbient = mix(SunAmbient, mix(SkyGround, SKY_TOP, NdotU * 0.25 + 0.25), 0.5);

        #ifdef IS_IRIS
            if(lightningBoltPosition.w > 0) {
                float VdotLi = 1 - min(1, distance(lightningBoltPosition.xyz, PlayerPos) * 0.01);
                vec3 LiBPN = normalize((player_view(lightningBoltPosition.xyz, false) - ViewPos));
                float NdotLi = max(0, dot(TBN[2], LiBPN)) * 0.8 + 0.2;
                SunAmbient += vec3(1) * NdotLi * VdotLi;
            }
        #endif
    #endif

    #ifdef HANDHELD_LIGHTS
        float Dist = length(ViewPos);

        float HandheldLight = max((heldBlockLightValue - Dist) / 15.0, 0) * max(0, dot(-ViewPosN, TBN[2]));
        HandheldLight = pow(HandheldLight, 4.0 - HANDHELD_FALLOFF_CURVE);
        LightmapCoords.x = max(LightmapCoords.x, HandheldLight);
    #endif

    #ifdef LM_FLICKER
        LightmapCoords.x *= (1 - LM_FLICKER_STRENGTH) + texture(noisetex, vec2(frameTimeCounter / 8, 0)).r * LM_FLICKER_STRENGTH;
    #endif

    #ifndef DIMENSION_OVERWORLD
        LightmapCoords.y = 1;
    #endif

    return LightmapCoords;
}

vec3 tweak_lightmap(vec3 PlayerPos, vec2 LightmapCoords, vec2 FragCoord) {
    vec3 LightColorFinal = SUN_AMBIENT;
    #ifdef VOXY_TERRAIN
        LightmapCoords = tweak_lightmap_vertex(LightmapCoords, LightColorFinal, normalize(ViewPos), PlayerPos);
    #endif
    #ifdef PBR_NORMAL
        vec3 PackNormal; float PackAo;
        decode_normal(texcoord, PackNormal, PackAo);
        PackNormal = TBN * PackNormal;
        
    #else
        vec3 PackNormal = TBN[2];
    #endif
    #ifdef PBR_SPECULAR
        float Smoothness, F0, PackSSS, Emissiveness;
        decode_specular(texcoord, Smoothness, F0, PackSSS, Emissiveness);
    #endif
    #ifndef DIMENSION_NETHER
        #ifdef DIMENSION_END
            float NdotL = max(0, dot(TBN[2], gbufferModelView[1].xyz));
        #else
            float NdotL = dot(PackNormal, sunOrMoonPosN);
        #endif

        float NdotLflat = dot(TBN[2], sunOrMoonPosN);

        #ifndef DIMENSION_END
            vec3 ViewPosN = normalize(ViewPos);
            float Shadow = 0;
            #ifdef DYNAMIC_SHADOWS
                float SSSStrength = float(material > 10001) * PBR_SSS_STRENGTH; // Subsurface scattering
                #ifdef PBR_SPECULAR
                    SSSStrength = max(SSSStrength, 0);
                #endif
                bool DoSSS = SSSStrength > 0;
                if(NdotLflat > -1e-6 || DoSSS) {
                    float ShadowS = 1, ShadowD = 1;
                    float Fade = shadow_fade(PlayerPos, shadowDistance);

                    if(Fade < 1) {
                        ShadowD = get_shadow_dynamic(ViewPos, PlayerPos, false, TBN[2], NdotL, LightmapCoords.y, DoSSS, FragCoord);

                        if(DoSSS) {
                            LightColorFinal += SUN_DIRECT * ShadowD * exp(-(1 - SSSStrength) * 5 * abs(NdotL)) * max(ISOTROPIC_PHASE, xlf_phase(dot(ViewPosN, sunOrMoonPosN), 0.6)) * 4 * (1-Fade);
                        }
                    }
                    if(Fade > 0) {
                        ShadowS = get_shadow_static(LightmapCoords.y);
                    }
                    
                    Shadow = mix(ShadowD, ShadowS, Fade);
                }
            #else
                if(NdotLflat > 0)
                    Shadow = get_shadow_static(LightmapCoords.y);
            #endif
            NdotL = max(0, NdotL) * Shadow;
            #ifdef PBR_SPECULAR
                if(NdotLflat > 0) {
                    vec3 H = normalize(sunOrMoonPosN - ViewPosN);
                    float F = schlick(PackNormal, -ViewPosN, F0);
                    NdotL += NdotL * PI * cook_torrance(-ViewPosN, sunOrMoonPosN, PackNormal, smoothness_to_roughness(Smoothness), H, F);
                }
            #endif
        #endif
        LightColorFinal += SUN_DIRECT * NdotL;
    #endif

    const vec3 TorchColor = to_linear(vec3(f_LM_RED, f_LM_GREEN, f_LM_BLUE));
    float MinLight = clamp(MIN_LIGHT_AMOUNT + screenBrightness * 0.1 - 0.1, 0.0, 0.5);
    MinLight = to_linear(MinLight);
    MinLight += nightVision / 3;

    float TorchPow = LightmapCoords.x;
    #ifdef PBR_SPECULAR
        TorchPow += Emissiveness;
    #endif
    LightColorFinal = TorchColor * TorchPow + mix(vec3(MinLight), LightColorFinal, LightmapCoords.y);
    LightColorFinal *= 1 - darknessLightFactor;

    #ifdef PBR_NORMAL
        LightColorFinal *= PackAo;
    #endif

    return LightColorFinal;
}
