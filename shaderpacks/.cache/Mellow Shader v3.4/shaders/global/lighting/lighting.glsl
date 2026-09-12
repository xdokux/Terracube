// Never include this file directly. Use gbuffers.fsh/vsh instead
#include "/global/voxelisation.glsl"
vec2 tweak_lightmap_vertex(vec2 LightmapCoords, inout vec3 SunAmbient, inout vec3 SunDirect, vec3 ViewPosN, vec3 Normal, vec3 PlayerPos) {
    LightmapCoords = max(LightmapCoords * 1.06667 - 0.0625, 0);

    LightmapCoords.x = pow(LightmapCoords.x, 4.0001 - LM_FALLOFF_CURVE);

    #ifdef DIMENSION_OVERWORLD
        // Combine ambient lighting with the sky and some other tricks to make it less flat
        float NdotU = clamp(dot(gbufferModelView[1].xyz, Normal), -1, 1);
        vec3 SkyGround = SKY_GROUND + get_sun_glare(clamp(dot(Normal, sunPosN), -1, 1));
        SunAmbient = mix(SunAmbient, mix(SkyGround, SKY_TOP, NdotU * 0.5 + 0.5), 0.4);

        #ifdef IS_IRIS
            if(lightningBoltPosition.w > 0) {
                float VdotLi = 1 - min(1, distance(lightningBoltPosition.xyz, PlayerPos) * 0.01);
                vec3 LiBPN = normalize((player_view(lightningBoltPosition.xyz, false) - ViewPos));
                float NdotLi = max(0, dot(Normal, LiBPN)) * 0.8 + 0.2;
                SunAmbient += vec3(1) * NdotLi * VdotLi;
            }
        #endif
    #endif

    #ifdef HANDHELD_LIGHTS
        #ifdef IS_IRIS
            vec3 ViewPosOffset = player_view(PlayerPos + relativeEyePosition, false);
        #else
            vec3 ViewPosOffset = ViewPos;
        #endif
        float Dist = length(ViewPosOffset);

        float HandheldLight = max((heldBlockLightValue - Dist) / 15.0, 0);
        #ifndef GBUFFERS_BASIC
            HandheldLight *= max(0, dot(-normalize(ViewPosOffset), Normal));
        #endif
        HandheldLight = pow(HandheldLight, 4.0 - HANDHELD_FALLOFF_CURVE);
        LightmapCoords.x = max(LightmapCoords.x, HandheldLight);
    #endif

    #ifdef LM_FLICKER
        LightmapCoords.x *= (1 - LM_FLICKER_STRENGTH) + texture(noisetex, vec2(frameTimeCounter / 8, 0)).r * LM_FLICKER_STRENGTH;
    #endif

    #ifndef DIMENSION_OVERWORLD
        LightmapCoords.y = 1;
    #endif

    #if (defined DYNAMIC_SHADOWS) && (defined DIMENSION_OVERWORLD)
        SunDirect *= 1.2;
        SunAmbient *= 0.85;
    #endif

    return LightmapCoords;
}

vec3 tweak_lightmap(vec3 Albedo, vec3 PlayerPos, vec2 LightmapCoords, vec2 texcoord, vec3 ScreenPos, mat3 TBN, float Dither, float PomShadow) {
    vec3 LightColorFinal = SUN_AMBIENT;
    #ifdef VOXY_TERRAIN
        LightmapCoords = tweak_lightmap_vertex(LightmapCoords, LightColorFinal, SUN_DIRECT, normalize(ViewPos), TBN[2], PlayerPos);
    #endif
    #ifdef PBR_NORMAL
        vec3 PackNormal; float PackAo;
        decode_normal(texcoord, PackNormal, PackAo);
        PackNormal = TBN * PackNormal;
        LightColorFinal *= PackAo;
    #else
        vec3 PackNormal = TBN[2];
    #endif
    #ifdef PBR_SPECULAR
        float Smoothness, F0, PackSSS, Porosity, Emissiveness;
        decode_specular(texcoord, Smoothness, F0, PackSSS, Porosity, Emissiveness);
    #endif
    #if (defined DH_TERRAIN) || (defined VOXY_TERRAIN)
        bool IsDH = true;
    #else
        bool IsDH = false;
    #endif
    vec3 ViewPosN = normalize(ViewPos);
    #if (defined DIMENSION_OVERWORLD) || (defined DIMENSION_END)
        #ifdef DIMENSION_END
            float NdotL = max(0, dot(TBN[2], gbufferModelView[1].xyz));
        #else
            float NdotL = dot(PackNormal, slpN);
        #endif

        NdotL *= PomShadow;
        

        #ifndef DIMENSION_END
            vec3 Shadow = vec3(0);
            float NdotLflat = dot(TBN[2], slpN);
            #ifdef DYNAMIC_SHADOWS
                #ifdef SHADOW_LIGHTLEAK_PREVENTION
                    NdotL *= LightmapCoords.y;
                #else
                    NdotL *= ScreenPos.z < 0.56 ? LightmapCoords.y : 1; // Fix lightleak on the hand
                #endif
                
                float SSSStrength = float(material > 10001) * PBR_SSS_STRENGTH; // Subsurface scattering
                #ifdef PBR_SPECULAR
                    SSSStrength = max(SSSStrength, PackSSS);
                #endif
                bool DoSSS = SSSStrength > 0;
                if(NdotLflat > -1e-6 || DoSSS) {
                    vec3 ShadowS = vec3(1), ShadowD = vec3(1);
                    float Fade = shadow_fade(PlayerPos, shadowDistance);

                    if(Fade < 1) {
                        ShadowD = get_shadow_dynamic(ViewPos, PlayerPos, false, TBN[2], NdotL, LightmapCoords.y, glcolor.a, DoSSS, Dither);

                        if(DoSSS) {
                            LightColorFinal += SUN_DIRECT * ShadowD * exp(-(1 - SSSStrength) * 5 * abs(NdotL)) * max(ISOTROPIC_PHASE, xlf_phase(dot(ViewPosN, slpN), 0.6)) * 4 * (1-Fade);
                        }
                    }
                    if(Fade > 0) {
                        ShadowS = get_shadow_static(LightmapCoords.y);
                    }
                    
                    Shadow = mix(ShadowD, ShadowS, Fade);
                }
            #else
                if(NdotLflat > -1e-6)
                    Shadow = get_shadow_static(LightmapCoords.y);
            #endif
            NdotL = max(0, NdotL);
        #else
            vec3 Shadow = vec3(1);
        #endif
    #endif

    vec3 TorchColor = to_linear(vec3(f_LM_RED, f_LM_GREEN, f_LM_BLUE));
    TorchColor = sample_floodfill(PlayerPos, TBN[2], TorchColor);
    float TorchPow = LightmapCoords.x;
    #ifdef PBR_SPECULAR
        TorchPow += Emissiveness;
    #endif
    LightColorFinal = TorchColor * TorchPow + mix(get_min_light(), LightColorFinal, LightmapCoords.y);
    #if (defined DIMENSION_OVERWORLD) || (defined DIMENSION_END)
        LightColorFinal += SUN_DIRECT * NdotL * Shadow;
    #endif
    LightColorFinal *= 1 - darknessLightFactor;
    #ifdef PBR_SPECULAR
        LightColorFinal *= 1 - Porosity * wetness * 0.66 * LightmapCoords.y;
    #endif

    LightColorFinal *= Albedo;
    #ifdef PBR_SPECULAR
        if(material != 10001 && !(material >= 10003 && material <= 10006)) {
            bool HandleAsMetal = false;
            #ifdef PBR_SPECULAR_RP_REFLECTIONS
                HandleAsMetal = F0 >= 230.0 / 255.0;
            #endif
            if(HandleAsMetal) {
                float Metalness = LightmapCoords.y * linstep(PBR_SPECULAR_RP_REFLECTIONS_THRESHOLD, 0.75, Smoothness); 
                LightColorFinal *= mix(vec3(1), Albedo*METAL_DIFFUSE_AMOUNT, Metalness);
            }
            #ifdef DIMENSION_OVERWORLD
                if(NdotL > 0) {
                    vec3 H = normalize(slpN - ViewPosN);
                    float F = schlick(H, -ViewPosN, F0);
                    vec3 Specular = SUN_DIRECT * cook_torrance(-ViewPosN, slpN, PackNormal, 1 - Smoothness, H, F);
                    Specular *= HandleAsMetal ? Albedo : vec3(1);
                    LightColorFinal += Specular * NdotL * Shadow;
                }
            #endif
            #ifdef PBR_SPECULAR_RP_REFLECTIONS
                if(Smoothness > PBR_SPECULAR_RP_REFLECTIONS_THRESHOLD) {
                    float F = schlick(PackNormal, -ViewPosN, F0);
                    vec3 Reflection = get_reflection(ScreenPos, ViewPos, ViewPosN, PackNormal, Dither, F, Smoothness, 1, LightmapCoords.y, false, IsDH);
                    Reflection *= HandleAsMetal ? Albedo : vec3(1);
                    LightColorFinal += Smoothness * F * Reflection;
                }
            #endif
        }
    #endif

    return LightColorFinal;
}
