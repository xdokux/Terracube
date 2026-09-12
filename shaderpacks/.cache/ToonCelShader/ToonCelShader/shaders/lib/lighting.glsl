#ifndef LIGHTING_GLSL
#define LIGHTING_GLSL

#include "settings.glsl"

uniform vec3 shadowLightPosition;
uniform float rainStrength;

vec3 getShadowLightDirection() {
    return normalize(shadowLightPosition);
}

float getDayFactor(vec3 lightDir) {
    return clamp(lightDir.y * 1.3 + 0.15, 0.0, 1.0);
}

vec3 getSunMoonColor(float dayFactor) {
    vec3 day   = vec3(1.05, 1.0, 0.95);
    vec3 night = vec3(0.35, 0.4, 0.6);
    return mix(night, day, smoothstep(0.0, 0.4, dayFactor)) * mix(1.0, 0.6, rainStrength);
}

// The core toon-shading step: quantize continuous N.L into a small
// number of discrete bands rather than a smooth gradient. This is
// what actually produces the "cel" look - everything else in this
// pack (outlines, flat color) supports this one idea.
float bandedDiffuse(vec3 normal, vec3 lightDir) {
    float nDotL = max(dot(normal, lightDir), 0.0);
    float banded = floor(nDotL * float(LIGHT_BANDS)) / float(LIGHT_BANDS);
    // Smooth the band edges very slightly so it doesn't look like a
    // broken texture at a distance - a tiny amount, most of the
    // "step" character is preserved.
    return mix(banded, nDotL, 0.08);
}

// Fresnel-style rim light - cheap way to add a stylized glow around
// silhouette edges of entities, which reads well alongside outlines.
float rimLight(vec3 normal, vec3 viewDir) {
    float rim = 1.0 - max(dot(normal, viewDir), 0.0);
    return pow(rim, 3.0) * RIM_LIGHT_STRENGTH;
}

#endif // LIGHTING_GLSL
