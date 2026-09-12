vec3 get_lava_fog(float dist, vec3 color) {
    const vec3 LAVA_FOG_COLOR = srgb_linear(vec3(0.65, 0.3, 0.1));
    const vec3 PSNOW_FOG_COLOR = srgb_linear(vec3(0.5, 0.6, 0.8));

    if (isEyeInWater == 2) {
        dist = clamp(dist / 2, 0, 1);
        return mix(color, LAVA_FOG_COLOR, dist);
    }
    else if (isEyeInWater == 3) {
        dist = clamp(dist / 2, 0, 1);
        return mix(color, PSNOW_FOG_COLOR, dist);
    }
    return color;
}

vec3 get_border_fog(float Dist, vec3 Color, vec3 SkyColor) {
    const int BORDER_FOG_FALLOFF = 3;
    const float BORDER_FOG_STRENGTH = 1;
    #ifdef DIMENSION_NETHER
        const int Falloff = max(0, BORDER_FOG_FALLOFF - 2);
    #else
        const int Falloff = BORDER_FOG_FALLOFF;
    #endif

    float Strength = Dist / farLod;
    for(int i = 1; i <= Falloff; i++)
        Strength *= Strength;

    Strength = min(1, (1-smoothstep(farLod - 32, farLod - 16, Dist)) * exp(-3 * BORDER_FOG_STRENGTH * Strength));

    return mix(SkyColor, Color, Strength);
}

vec3 get_blindness_fog(float Dist, vec3 Color) {
    Dist = clamp(1.0 - exp(-3.0 * Dist / 10), 0, 1) * max(darknessFactor, blindness);
    return Color * (1 - Dist);
}

vec3 get_fog_main(vec3 PlayerPos, vec3 Color, vec3 SkyColor, float Depth) {
    float Dist = length(PlayerPos);

    #ifdef BORDER_FOG
    if (Depth < 1) {
        Color.rgb = get_border_fog(Dist, Color.rgb, SkyColor);
    }
    #endif
    Color.rgb = get_lava_fog(Dist, Color.rgb);
    Color.rgb = get_blindness_fog(Dist, Color.rgb);
    return Color;
}
