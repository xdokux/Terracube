float water_fog() {
    vec2 ScreenPos = gl_FragCoord.xy * resolutionInv;
    float TerrainDepth = texture2D(depthtex1, ScreenPos).x;
    float DepthDiff = linearize_depth(TerrainDepth) - linearize_depth(gl_FragCoord.z);
    return clamp(DepthDiff * (1.0/48.0), 0.0, 1.0) * WATER_FOG_STRENGTH;
}

vec4 get_fancy_water(vec3 ScreenPos, vec3 ViewPos, vec4 BaseColor, float SkyBrightness, mat3 TBN, bool IsDH) {
    // Simple fog
    #ifndef DISTANT_HORIZONS
    if (isEyeInWater == 0) {
        BaseColor.a = min(BaseColor.a + water_fog(), 1.0);
    }
    #endif

    // Simple fog
    #if defined ATMOSPHERIC_FOG || defined BORDER_FOG || defined DIMENSION_END
    vec3 PlayerPos = to_player_pos(ViewPos);
    vec3 ViewPosN = fast_normalize(ViewPos);
    vec3 SkyColor = get_sky(ViewPosN, get_sun_glare(dot(ViewPosN, sunPosN)));
    float Dither = dither(gl_FragCoord.xy);
    BaseColor.rgb = get_fog_main(ScreenPos, PlayerPos, BaseColor.rgb, gl_FragCoord.z, SkyColor, dot(ViewPosN, sunPosN), Dither, IsDH);
    #endif

    return BaseColor;
}
