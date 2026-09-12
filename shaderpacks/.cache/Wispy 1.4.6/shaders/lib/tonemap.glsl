// Linear color space conversion
#define to_linear(sRGB) (sRGB * sRGB)

// Fast Reinhard tonemapper with white point correction
vec3 apply_tonemap(vec3 x) {
    const float whitePoint = 1.1;
    return (x * (1.0 + x / (whitePoint * whitePoint))) / (1.0 + x);
}

// Optimized saturation using Rec.709 coefficients
vec3 apply_saturation(vec3 color, float sat) {
    float luminance = dot(color, vec4(0.2126, 0.7152, 0.0722, 0.0).xyz);
    return mix(vec3(luminance), color, sat);
}

// Optimized vibrance
vec3 apply_vibrance(vec3 color, float intensity) {
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return mix(vec3(luminance), color, intensity);
}

// Contrast adjustment with safer mid-point anchoring
vec3 apply_contrast(vec3 color, float contrast) {
    return (color - 0.45) * contrast + 0.45;
}

// Luminance-preserving color mixing
vec3 mix_preserve_c1lum(vec3 c1, vec3 c2, float weight) {
    float l1 = dot(c1, vec3(0.2126, 0.7152, 0.0722));
    vec3 cMixed = mix(c1, c2, weight);
    float lMixed = dot(cMixed, vec3(0.2126, 0.7152, 0.0722)) + 1e-5;
    return cMixed * (l1 / lMixed);
}

// Underwater tinting logic
vec3 tint_underwater(vec3 finalColor) {
    if (isEyeInWater == 1) {
        vec3 waterColor = vec3(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE);
        waterColor *= waterColor;
        waterColor = mix_preserve_c1lum(waterColor, fogColor, f_BIOME_WATER_CONTRIBUTION);
        float surfaceDepth = 1.0 - clamp(eyeBrightnessSmooth.y / 240.0, 0.0, 1.0);
        finalColor = mix_preserve_c1lum(finalColor, waterColor, surfaceDepth * 0.85);
    }
    return finalColor;
}
