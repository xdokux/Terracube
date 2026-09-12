// Very simple and inaccurate, but it's better than nothing.
float water_fog() {
    vec2 ScreenPos = gl_FragCoord.xy * resolutionInv;
    float TerrainDepth = texture(depthtex1, ScreenPos).x;
    TerrainDepth = linearize_depth(TerrainDepth);
    float ScreenDepth = linearize_depth(gl_FragCoord.z);
    return smoothstep(0, 48, TerrainDepth - ScreenDepth) * WATER_FOG_STRENGTH;
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

vec3 sky_reflection(vec3 ReflectedVec, float WNy, float Dist) {
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
        return to_linear(fogColor.rgb);
    #endif
}

vec3 flipped_image_ref(vec3 RVec, float Dist, vec3 ViewPos, float WNy, bool IsDH) {
    #ifdef DISTANT_HORIZONS
    float Offset = min(1000, 50 + dhRenderDistance / 4);
    #else
    float Offset = 50 + far / 4;
    #endif

    vec3 SamplePos = view_screen(ViewPos + RVec * Offset, IsDH);
    if(SamplePos.xy == vec2(clamp(SamplePos.x, -0.1, 1.1), clamp(SamplePos.y, 0, 1))) {
        bool IsDHReal;
        float RealDepth = get_depth_solid_lq(SamplePos.xy, IsDHReal);
        #ifdef DISTANT_HORIZONS
            if(SamplePos.z >= 1) {
                SamplePos = view_screen(ViewPos + RVec * Offset, true);
            }
        #endif
        if(SamplePos.z < 1 && SamplePos.z > 0.56 && RealDepth < 1) {
            SamplePos.z = RealDepth;
            vec3 ViewPosReal = screen_view(SamplePos, IsDHReal);
            if(len2(ViewPosReal) + 25 > len2(ViewPos)) {
                return texture(gaux1, SamplePos.xy).rgb;
            }
        }
    }
    return sky_reflection(RVec, WNy, Dist);
}

vec3 ssr(vec3 RVec, float Dist, vec3 ViewPos, float Fresnel, float WNy, float Noise, bool IsDH) {
    vec3 ScreenPos = vec3(gl_FragCoord.xy * resolutionInv, gl_FragCoord.z);
    // Convert RVec to screenspace
    vec3 Offset = normalize(view_screen(ViewPos + RVec, IsDH) - ScreenPos);
    vec3 Len = (step(0, Offset) - ScreenPos) / Offset;
    float MinLen = min(Len.x, min(Len.y, Len.z)) / SSR_STEPS;
    Offset *= MinLen;

    vec3 ExpectedPos = ScreenPos + Offset * Noise;
    for (int i = 1; i <= SSR_STEPS; i++) {
        float RealDepth = get_depth_solid_lq(ExpectedPos.xy, IsDH);
        if (RealDepth < 0.56) {
            break;
        }

        if (ExpectedPos.z > RealDepth) {
            // Depth based rejection
            if (ExpectedPos.z - RealDepth > Offset.z * (0.5 * SSR_STEPS)) {
                break;
            }

            // Binary refinement
            for (int j = 1; j <= int(round(Fresnel * 3)); j++) {
                Offset /= 2;
                vec3 EPos1 = ExpectedPos - Offset;
                float RDepth1 = get_depth_solid_lq(EPos1.xy, IsDH);
                if (EPos1.z > RDepth1) {
                    ExpectedPos = EPos1;
                }
            }
            return texture(gaux1, ExpectedPos.xy).rgb;
        }
        ExpectedPos += Offset;
    }
    #ifdef DISTANT_HORIZONS
        return flipped_image_ref(RVec, Dist, ViewPos, WNy, IsDH);
    #endif
    return sky_reflection(RVec, WNy, Dist);
}



vec4 get_fancy_water(vec3 ScreenPos, vec3 ViewPos, vec4 BaseColor, float SkyBrightness, mat3 TBN, bool IsDH) {
    #ifndef DISTANT_HORIZONS
        if (isEyeInWater == 0) {
            BaseColor.a = min(BaseColor.a + water_fog(), 1);
        }
    #endif
    vec3 ViewPosN = normalize(ViewPos);
    vec3 PlayerPos = view_player(ViewPos, IsDH);

    float Dither = dither(gl_FragCoord.xy);

    #if REFLECTIONS != 0
        vec3 WorldNormal = view_player(TBN[2], IsDH);
        #ifdef WATER_NORMALS
            vec3 NormalMap = get_water_normal(PlayerPos.xz + cameraPosition.xz, WorldNormal);
            vec3 WaterNormal = TBN * NormalMap;
        #else
            vec3 WaterNormal = TBN[2];
        #endif

        vec3 ReflectedVec = reflect(ViewPosN, WaterNormal);
        float Dist = dot(ReflectedVec, sunPosN);
        float Fresnel = schlick(ViewPosN, WaterNormal) * SkyBrightness;

        if (WorldNormal.y > -0.01) { // Prevent reflections underwater and other weird scenarios
            #if REFLECTIONS == 1
                vec3 Reflection = sky_reflection(ReflectedVec, WorldNormal.y, Dist);
            #elif REFLECTIONS == 2
                vec3 Reflection = ssr(ReflectedVec, Dist, ViewPos, Fresnel, WorldNormal.y, Dither, IsDH);
            #else
                vec3 Reflection = flipped_image_ref(ReflectedVec, Dist, ViewPos, WorldNormal.y, IsDH);
            #endif
            BaseColor.rgb = mix(BaseColor.rgb, Reflection, Fresnel);
        }
    #endif

    vec3 SkyColor = get_sky(ViewPosN, get_sun_glare(dot(ViewPosN, sunPosN)));
    BaseColor.rgb = get_fog_main(ScreenPos, PlayerPos, BaseColor.rgb, gl_FragCoord.z, SkyColor, dot(ViewPosN, sunPosN), Dither, IsDH);
    return BaseColor;
}
