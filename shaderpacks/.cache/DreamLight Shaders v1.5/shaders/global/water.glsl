// Distance through the water volume, in blocks, for the current fragment.
// Reused by the fog, foam and caustics so we only pay for the depth fetch once.
float water_thickness() {
    vec2 ScreenPos = gl_FragCoord.xy * resolutionInv;
    float TerrainDepth = linearize_depth(texture2D(depthtex1, ScreenPos).x);
    float ScreenDepth = linearize_depth(gl_FragCoord.z);
    return TerrainDepth - ScreenDepth;
}

// Improved depth-based water fog with exponential falloff
float water_fog(float DepthDiff) {
    // Exponential falloff for more natural underwater look
    return (1.0 - exp(-DepthDiff * WATER_FOG_STRENGTH * 0.08)) * step(0.0, DepthDiff);
}

#ifdef WATER_FOAM
// Shoreline foam: bright where the water volume is thin, i.e. right up against
// terrain. Broken up with noise so it reads as foam rather than a clean band.
float get_water_foam(float DepthDiff, vec2 WorldXZ) {
    float Edge = 1.0 - smoothstep(0.0, WATER_FOAM_WIDTH, max(DepthDiff, 0.0));
    if (Edge <= 0.0) return 0.0;

    float T = frameTimeCounter * 0.35;
    float N = fbm_fast(WorldXZ * 24.0 + vec2(T, -T * 0.7), 2);
    N += fbm_fast(WorldXZ * 52.0 - vec2(T * 1.3, T * 0.4), 2) * 0.5;
    N /= 1.5;

    // Sharpen into streaks, and always keep a thin solid line at the contact edge
    float Streaks = smoothstep(0.42, 0.62, N * (0.55 + Edge * 0.65));
    float Contact = smoothstep(0.75, 1.0, Edge);
    return clamp(max(Streaks * Edge, Contact), 0.0, 1.0);
}
#endif

#ifdef WATER_CAUSTICS
// Cheap caustics: two counter-rotating noise layers, sharpened with a power
// curve so the bright filaments stay thin. Fades out as the water gets deeper.
float get_water_caustics(vec2 WorldXZ, float DepthDiff) {
    float T = frameTimeCounter * 0.5;
    vec2 C1 = WorldXZ * 8.0 + vec2(T * 0.12, T * 0.09);
    vec2 C2 = rotate(WorldXZ * 11.0, 2.1) - vec2(T * 0.07, T * 0.14);

    float N = fbm_fast(C1, 2) + fbm_fast(C2, 2);
    N = 1.0 - abs(N - 0.75) * 2.0;
    N = pow4(clamp(N, 0.0, 1.0));

    // Strongest in shallow water, gone by the time it is deep
    float Depth = clamp(DepthDiff, 0.0, 24.0);
    float Falloff = smoothstep(0.0, 1.5, Depth) * (1.0 - smoothstep(6.0, 24.0, Depth));
    return N * Falloff;
}
#endif

vec3 tint_underwater(vec3 FinalColor) {
    if (isEyeInWater == 1) {
        vec3 WaterColor = to_linear(vec3(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE));
        WaterColor = mix_preserve_c1lum(WaterColor, fogColor, f_BIOME_WATER_CONTRIBUTION);
        float DistFromSurface = 1 - eyeBrightnessSmooth.y / 240.;
        FinalColor = mix_preserve_c1lum(FinalColor, WaterColor, DistFromSurface);
    }
    return FinalColor;
}

float schlick(vec3 V, vec3 N) {
    const float R = 0.1;
    float Theta = clamp(1 - dot(-V, N), 0, 1);
    return R + (1 - R) * (pow(Theta, 5.0));
}

vec3 get_water_normal(vec2 Coords, vec3 WorldNormal) {
    if (abs(WorldNormal.y) < 0.99) {
        Coords -= frameTimeCounter * normalize(WorldNormal.xz) * 3;
    }
    vec2 N = noise_water(Coords);
    return normalize(vec3(N.x, N.y, 1 - (N.x * N.x + N.y * N.y)));
}

vec3 sky_reflection(vec3 ReflectedVec, float Dist, float WNy) {
    #ifdef DIMENSION_OVERWORLD
    vec3 SunGlare = get_sun_glare(Dist);
    vec3 Reflection = get_sky(ReflectedVec, SunGlare);
    #ifdef REFLECT_SUN
    if (WNy > 0.01) { // Prevent sun from being reflected on sides of blocks
        Reflection.rgb += round_sun(Dist) * 4 * isOutdoorsSmooth;
    }
    #endif
    return Reflection;
    #else
    return fogColor.rgb;
    #endif
}

vec3 ssr(vec3 RVec, float Dist, vec3 ViewPos, float Fresnel, float WNy, bool IsDH) {
    if (WNy > -0.01) { // Prevent reflections underwater and other weird scenarios
        vec3 ScreenPos = vec3(gl_FragCoord.xy * resolutionInv, gl_FragCoord.z);
        // Convert RVec to screenspace
        vec3 Offset = normalize(view_screen(ViewPos + RVec, IsDH) - ScreenPos);
        vec3 Len = (step(0, Offset) - ScreenPos) / Offset;
        float MinLen = min(Len.x, min(Len.y, Len.z)) / SSR_STEPS;
        Offset *= MinLen;

        float Noise = dither(gl_FragCoord.xy);
        vec3 ExpectedPos = ScreenPos + Offset * Noise;
        for (int i = 1; i <= SSR_STEPS; i++) {
            float RealDepth = get_depth_solid(ExpectedPos.xy, IsDH);
            if (RealDepth < 0.56) {
                break;
            }

            if (ExpectedPos.z > RealDepth) {
                // Depth based rejection
                if (ExpectedPos.z - RealDepth > Offset.z * 4) {
                    break;
                }

                // Binary refinement
                for (int j = 1; j <= int(round(Fresnel * 3)); j++) {
                    Offset /= 2;
                    vec3 EPos1 = ExpectedPos - Offset;
                    float RDepth1 = get_depth_solid(EPos1.xy, IsDH);
                    if (EPos1.z > RDepth1) {
                        ExpectedPos = EPos1;
                    }
                }
                return texture2D(gaux1, ExpectedPos.xy).rgb;
            }
            ExpectedPos += Offset;
        }
    }
    return sky_reflection(RVec, Dist, WNy);
}

vec3 flipped_image_ref(vec3 RVec, float Dist, vec3 ViewPos, float WNy, bool IsDH) {
    if (WNy > -0.01) {
        vec3 SamplePos = view_screen(ViewPos + RVec * 100, IsDH);
        if(SamplePos.xy == clamp(SamplePos.xy, 0, 1)) {
            float RealDepth = texture(depthtex1, SamplePos.xy).r;
            if(SamplePos.z < 1 && SamplePos.z > 0.56 && RealDepth < SamplePos.z) {
                SamplePos.z = RealDepth;
                vec3 ViewPosReal = to_view_pos(SamplePos, IsDH);
                if(len2(ViewPosReal) + 25 > len2(ViewPos)) {
                    return texture(gaux1, SamplePos.xy).rgb;
                }
            }
        }
    }
    return sky_reflection(RVec, Dist, WNy);
}

vec4 get_fancy_water(vec3 ScreenPos, vec3 ViewPos, vec4 BaseColor, float SkyBrightness, mat3 TBN, bool IsDH) {
    #if !defined DISTANT_HORIZONS || defined WATER_FOAM || defined WATER_CAUSTICS
        float Thickness = water_thickness();
    #endif
    #ifndef DISTANT_HORIZONS
        if (isEyeInWater == 0) {
            BaseColor.a = min(BaseColor.a + water_fog(Thickness), 1);
        }
    #endif
    vec3 ViewPosN = normalize(ViewPos);
    vec3 PlayerPos = to_player_pos(ViewPos);

    #if defined WATER_CAUSTICS || defined WATER_FOAM
        vec2 WorldXZ = PlayerPos.xz + cameraPosition.xz;
    #endif

    #ifdef WATER_CAUSTICS
        if (isEyeInWater == 0 && !IsDH) {
            float Caustics = get_water_caustics(WorldXZ * 0.02, Thickness);
            BaseColor.rgb += Caustics * (SUN_DIRECT * 0.35 + SKY_TOP * 0.15)
                             * SkyBrightness * WATER_CAUSTICS_STRENGTH;
        }
    #endif

    #if REFLECTIONS != 0
        vec3 WorldNormal = to_player_pos(TBN[2]);
        #ifdef WATER_NORMALS
            vec3 NormalMap = get_water_normal(PlayerPos.xz + cameraPosition.xz, WorldNormal);
            vec3 WaterNormal = TBN * NormalMap;
        #else
            vec3 WaterNormal = TBN[2];
        #endif

        vec3 ReflectedVec = reflect(ViewPosN, WaterNormal);
        float Dist = dot(ReflectedVec, sunPosN);
        float Fresnel = schlick(ViewPosN, WaterNormal) * SkyBrightness;

        #if REFLECTIONS == 1
            vec3 Reflection = sky_reflection(ReflectedVec, Dist, WorldNormal.y);
        #elif REFLECTIONS == 2
            vec3 Reflection = ssr(ReflectedVec, Dist, ViewPos, Fresnel, WorldNormal.y, IsDH);
        #else
            vec3 Reflection = flipped_image_ref(ReflectedVec, Dist, ViewPos, WorldNormal.y, IsDH);
        #endif
        BaseColor.rgb = mix(BaseColor.rgb, Reflection, Fresnel);
    #endif

    #ifdef WATER_FOAM
        if (isEyeInWater == 0 && !IsDH) {
            float Foam = get_water_foam(Thickness, WorldXZ * 0.05);
            vec3 FoamColor = (SUN_DIRECT * 0.4 + SKY_TOP * 0.6 + SKY_GROUND * 0.4)
                             * mix(0.35, 1.0, SkyBrightness);
            BaseColor.rgb = mix(BaseColor.rgb, FoamColor, Foam * WATER_FOAM_STRENGTH);
            BaseColor.a = min(BaseColor.a + Foam * WATER_FOAM_STRENGTH, 1.0);
        }
    #endif

    vec3 SkyColor = get_sky(ViewPosN, get_sun_glare(dot(ViewPosN, sunPosN)));
    BaseColor.rgb = get_fog_main(PlayerPos, BaseColor.rgb, gl_FragCoord.z, SkyColor);
    return BaseColor;
}
