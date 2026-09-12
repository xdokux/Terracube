#ifndef CINDERLIGHT_OVERWORLD_BIOME_FOG_GLSL
#define CINDERLIGHT_OVERWORLD_BIOME_FOG_GLSL

// Iris smooths these camera-biome values in shaders.properties so biome borders
// transition without hard colour or density steps.
uniform float biomeFogTintR;
uniform float biomeFogTintG;
uniform float biomeFogTintB;
uniform float biomeFogDensity;

vec3 getOverworldBiomeFogTint() {
    vec3 tint = vec3(biomeFogTintR, biomeFogTintG, biomeFogTintB);

    // A missing/invalid custom uniform must preserve the original fog rather
    // than introduce black or undefined colour.
    float tintMinimum = min(tint.r, min(tint.g, tint.b));
    float tintMaximum = max(tint.r, max(tint.g, tint.b));
    if (tintMinimum < 0.5 || tintMaximum > 1.5) return vec3(0.800, 0.850, 0.900);

    return tint;
}

float getOverworldBiomeFogDensity() {
    // Density behavior is unchanged; invalid values fall back to the original.
    if (biomeFogDensity < 0.5 || biomeFogDensity > 1.5) return 1.0;
    return biomeFogDensity;
}

// Match a palette colour to a source luminance so biome tuning changes hue
// without changing fog brightness.
vec3 matchBiomeFogLuminance(vec3 palette, float sourceLuminance) {
    float paletteLuminance = max(luminance(palette), 1.0e-4);
    return palette * (max(sourceLuminance, 0.0) / paletteLuminance);
}

#endif
