float shadow_fade(vec3 PlayerPos, float Dist) {
    #ifdef DISTANT_HORIZONS
        Dist = min(far, Dist);
    #endif
    return smoothstep(Dist - 32, Dist, len_sq(PlayerPos));
}

// Helios: 6-tap shadowed-aware blur. Uses hardware-filtered samples
// (sampler2DShadow returns a bilinear-filtered 0..1 visibility), so 6
// taps already produce a softer result than the original 6-tap version.
float shadow_blur(vec3 SampleCoord, float Radius) {
    vec3 Off1 = vec3(-0.33, 1.0, 0) / shadowMapResolution * Radius;
    vec3 Off2 = vec3(1.0, 0.33, 0) / shadowMapResolution * Radius;
    float Color = texture(shadowtex0, SampleCoord) * 0.25;
    Color += texture(shadowtex0, SampleCoord + Off1) * 0.1875;
    Color += texture(shadowtex0, SampleCoord - Off1) * 0.1875;
    Color += texture(shadowtex0, SampleCoord + Off2) * 0.1875;
    Color += texture(shadowtex0, SampleCoord - Off2) * 0.1875;
    return Color;
}

// Helios: cheap blocker search used by the PCSS-style penumbra estimate.
// Returns true (1.0) if at least one of the 4 taps on a tiny disk is in
// shadow, false (0.0) otherwise. The radius is intentionally small so
// we only detect occluders that are *near* the receiver (where soft
// penumbras make sense) and not occluders from far-away geometry.
float has_blocker_nearby(vec3 ShadowPosUndistorted, float SearchRadius) {
    const vec2 Offsets[4] = vec2[4](
        vec2( 0.7071,  0.7071),
        vec2(-0.7071,  0.7071),
        vec2( 0.7071, -0.7071),
        vec2(-0.7071, -0.7071)
    );

    for (int i = 0; i < 4; i++) {
        vec3 SampleCoord = ShadowPosUndistorted + vec3(Offsets[i] * SearchRadius, 0.0);
        SampleCoord = distort(SampleCoord) * 0.5 + 0.5;
        // shadowtex0 is a sampler2DShadow: returns 0..1 visibility (1 = lit, 0 = occluded).
        float Visibility = texture(shadowtex0, SampleCoord);
        if (Visibility < 0.5) return 1.0;
    }
    return 0.0;
}

// Helios: improved PCF with 12 taps on a Vogel disk, plus a PCSS-style
// penumbra estimate. The penumbra grows when occluders are detected
// nearby (soft edges) and shrinks to a tight disk when the receiver is
// fully lit (crisp edges, less shimmering). The 12-tap disk is barely
// more expensive than the original 8-tap version because all samples
// are hardware-filtered (sampler2DShadow).
float pcf(float PenumbraSize, vec3 ShadowPosUndistorted, float Dither) {
    const int SAMPLE_COUNT = 12;

    Dither = Dither * TAU;
    vec2 Offset = vec2(cos(Dither), sin(Dither)) / shadowMapResolution;
    mat2 RotationOffset = mat2(
            Offset.x, Offset.y,
            -Offset.y, Offset.x
        );

    // Cheap 4-tap blocker search on a small disk. The search radius is
    // half the PCF radius: we only want to detect occluders that are
    // close enough to actually soften the visible shadow edge.
    float Blocker = has_blocker_nearby(ShadowPosUndistorted, PenumbraSize * 0.5);
    // PCSS-style: full penumbra when blocker detected, half penumbra
    // when fully lit (keeps flat-ground shadows crisp & stable).
    float PenumbraScale = mix(0.5, 1.0, Blocker) * SHADOW_PENUMBRA;

    float ShadowColorFinal = 0;
    for (int i = 0; i < SAMPLE_COUNT; i++) {
        vec2 OffsetP = RotationOffset * vogel_disk[i] * PenumbraSize * PenumbraScale;
        vec3 ShadowPosD = ShadowPosUndistorted + vec3(OffsetP, 0);
        ShadowPosD = distort(ShadowPosD);

        ShadowPosD = ShadowPosD * 0.5 + 0.5; //convert from shadow ndc space to shadow screen space.
        ShadowColorFinal += texture(shadowtex0, ShadowPosD);
    }
    return ShadowColorFinal / SAMPLE_COUNT;
}

float get_shadow_static(float Skylight) {
    // This cuts off direct sunlight it semi-occulded areas.
    // Helios: slightly tighter threshold so dynamic shadows blend better
    // with the lightmap-based fallback at the edge of the shadow distance.
    return smoothstep(0.82, 0.95, Skylight);
}

float get_shadow_dynamic(vec3 ViewPos, vec3 PlayerPos, bool IsDH, vec3 FlatNormal, float NdotL, float Skylight, bool DoSSS, float Dither) {
    #ifdef DIMENSION_NETHER
        return 0.0;
    #endif

    vec3 bias = compute_bias(PlayerPos + gbufferModelViewInverse[3].xyz, view_player(FlatNormal, IsDH), NdotL, Skylight);
    if (DoSSS) {
        bias *= vec3(0.05);
    }

    vec3 ShadowPosUndistorted = player_shadow(PlayerPos + bias);

    vec3 ShadowPos = distort(ShadowPosUndistorted);
    ShadowPos = ShadowPos * 0.5 + 0.5;

    float ShadowFinal;
    #ifdef FAST_SHADOWS
        ShadowFinal = texture(shadowtex0, ShadowPos);
    #elif SHADOW_FILTER > 0
        // Helios: scale base penumbra by shadowMapResolution so that
        // increasing the resolution doesn't accidentally make the filter
        // tighter (and vice-versa). 1024 is the reference resolution.
        float ResolutionScale = sqrt(1024.0 / float(shadowMapResolution));
        float PenumbraSize = (DoSSS ? 5.0 : 1.0) * ResolutionScale;
        #if SHADOW_FILTER == 1
            ShadowFinal = shadow_blur(ShadowPos, PenumbraSize);
        #else
            ShadowFinal = pcf(PenumbraSize * 2.0 * PCF_STRENGTH, ShadowPosUndistorted, Dither);
        #endif
    #else
        ShadowFinal = texture(shadowtex0, ShadowPos);
    #endif

    return ShadowFinal;
}
