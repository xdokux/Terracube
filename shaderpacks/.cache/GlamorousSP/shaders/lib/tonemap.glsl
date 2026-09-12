
#define to_linear(sRGB) ( sRGB * (sRGB * (sRGB * 0.305306011 + 0.682171111) + 0.012522878) )

vec3 apply_tonemap(vec3 X) {
    #if TONEMAP_OPERATOR == 1
    return ACESFilm(X);
    #elif TONEMAP_OPERATOR == 2
    return reinhard_jodie(X);
    #elif TONEMAP_OPERATOR == 3
    return ACES_slow(X);
    #elif TONEMAP_OPERATOR == 4
    return Hejl2015(X);
    #elif TONEMAP_OPERATOR == 5
    return Lottes(X);
    #elif TONEMAP_OPERATOR == 6
    return Uchimura(X);
    #endif
}

vec3 apply_saturation(vec3 Color, float Sat) {
    float luminance = get_luminance(Color);
    return mix(vec3(luminance), Color, Sat);
}

vec3 apply_vibrance(vec3 color, float intensity) {
    float mn = min(color.r, min(color.g, color.b));
    float mx = max(color.r, max(color.g, color.b));
    float sat = (1.0 - clamp(mx - mn, 0, 1)) * clamp(1.0 - mx, 0, 1) * get_luminance(color) * 5.0;
    vec3 lightness = vec3((mn + mx) * 0.5);

    return mix(color, mix(lightness, color, intensity), sat);
}

vec3 apply_contrast(vec3 color, float contrast) {
    return (color - 0.5) * contrast + 0.5;
}

// Mix colors, preserving the luminance of c1
vec3 mix_preserve_c1lum(vec3 C1, vec3 C2, float Weight) {
    float L1 = get_luminance(C1);

    vec3 CMixed = mix(C1, C2, Weight);
    float L = get_luminance(CMixed) + 1e-6;

    float Scale = L1 / L;

    return CMixed * Scale;
}

vec3 tint_underwater(vec3 FinalColor) {
    if (isEyeInWater == 1) {
        vec3 WaterColor = to_linear(vec3(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE));
        WaterColor = mix_preserve_c1lum(WaterColor, fogColor, f_BIOME_WATER_CONTRIBUTION);
        float DistFromSurface = 1 - eyeBrightnessSmooth.y / 240.;
        vec3 Tinted = WaterColor * DistFromSurface;
        FinalColor = mix_preserve_c1lum(FinalColor, WaterColor, DistFromSurface);
    }
    return FinalColor;
}

vec3 rgb_to_hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz),
                 vec4(c.gb, K.xy),
                 step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r),
                 vec4(c.r, p.yzx),
                 step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(
        abs(q.z + (q.w - q.y) / (6.0 * d + e)), // Hue
        d / (q.x + e),                          // Saturation
        q.x                                     // Value
    );
}

vec3 hsv_to_rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}