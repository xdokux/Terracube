

vec3 get_shadow_transparent(vec3 SampleCoords) {
    #ifdef COLORED_SHADOWS
        float Depth1 = texture(shadowtex1, SampleCoords);
            if (Depth1 < 0.001) {
                return vec3(Depth1);
            }
            float Depth = texture(shadowtex0, SampleCoords);
            if (Depth < 1) {
                vec4 ShadowCol = texture(shadowcolor0, SampleCoords.xy);

                ShadowCol.rgb = mix(vec3(1), ShadowCol.rgb, (1 - Depth));
                return ShadowCol.rgb * Depth1;
            }
        return vec3(Depth1);
    #else
        return vec3(texture(shadowtex0, SampleCoords));
    #endif
}

vec3 shadow_blur(vec3 SampleCoord, float Radius) {
    float d = 0.5 / shadowMapResolution * Radius;
    vec3 Color = get_shadow_transparent(SampleCoord + vec3(-d, -d, 0));
    Color +=      get_shadow_transparent(SampleCoord + vec3(-d,  d, 0));
    Color +=      get_shadow_transparent(SampleCoord + vec3( d, -d, 0));
    Color +=      get_shadow_transparent(SampleCoord + vec3( d,  d, 0));
    return Color * 0.25;
}


vec3 pcf(float PenumbraSize, vec3 ShadowPosUndistorted, float Dither) {
    const int SAMPLE_COUNT = 8;
    
    Dither = Dither * TAU;
    vec2 Offset = vec2(cos(Dither), sin(Dither)) / shadowMapResolution;
    mat2 RotationOffset = mat2(
            Offset.x, Offset.y,
            -Offset.y, Offset.x
        );

    vec3 ShadowColorFinal = vec3(0);
    for (int i = 0; i < SAMPLE_COUNT; i++) {
        vec2 OffsetP = RotationOffset * vogel_disk[i] * PenumbraSize;
        vec3 ShadowPosD = ShadowPosUndistorted + vec3(OffsetP, 0);
        ShadowPosD = distort(ShadowPosD);

        ShadowPosD = ShadowPosD * 0.5 + 0.5; //convert from shadow ndc space to shadow screen space.
        ShadowColorFinal += get_shadow_transparent(ShadowPosD);
    }
    return ShadowColorFinal / SAMPLE_COUNT;
}

vec3 get_shadow_static(float Skylight) {
    // This cuts off direct sunlight it semi-occulded areas.
    return vec3(smoothstep(0.85, 0.96, Skylight));
}

vec3 get_shadow_dynamic(vec3 ViewPos, vec3 PlayerPos, bool IsDH, vec3 FlatNormal, float NdotL, float Skylight, float Ao, bool DoSSS, float Dither) {
    vec3 bias = compute_bias(PlayerPos + gbufferModelViewInverse[3].xyz, view_player(FlatNormal, IsDH), NdotL, Skylight, Ao);
    if (DoSSS) {
        bias *= vec3(0.05);
    }

    vec3 ShadowPosUndistorted = player_shadow(PlayerPos + bias);
   
    vec3 ShadowPos = distort(ShadowPosUndistorted);
    ShadowPos = ShadowPos * 0.5 + 0.5;

    vec3 ShadowFinal;
    #if SHADOW_FILTER > 0
        float PenumbraSize = DoSSS ? 5 : 1;
        PenumbraSize *= Skylight;
        #if SHADOW_FILTER == 1
            ShadowFinal = shadow_blur(ShadowPos, PenumbraSize);
        #else
            ShadowFinal = pcf(PenumbraSize * 2 * PCF_STRENGTH, ShadowPosUndistorted, Dither);
        #endif
    #else
        ShadowFinal = get_shadow_transparent(ShadowPos);
    #endif

    return ShadowFinal;
}
