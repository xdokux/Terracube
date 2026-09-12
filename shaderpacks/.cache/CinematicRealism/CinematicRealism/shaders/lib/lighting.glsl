#ifndef LIGHTING_GLSL
#define LIGHTING_GLSL

#include "settings.glsl"

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform float rainStrength;

vec3 getShadowLightDirection() {
    return normalize(shadowLightPosition);
}

float halfLambert(vec3 normal, vec3 lightDir) {
    float nDotL = dot(normal, lightDir) * 0.5 + 0.5;
    return nDotL * nDotL;
}

float getDayFactor(vec3 sunDir) {
    return clamp(sunDir.y * 1.3 + 0.15, 0.0, 1.0);
}

// Golden-hour-forward color ramp: a wider, warmer sunset band than a
// purely physical model would give, since that's an explicit visual
// goal here rather than an accident to avoid.
vec3 getSunMoonColor(float dayFactor) {
    vec3 dayColor    = vec3(1.08, 1.02, 0.92);
    vec3 goldenColor = vec3(1.35, 0.72, 0.32);
    vec3 nightColor  = vec3(0.24, 0.32, 0.55);

    vec3 color = mix(nightColor, dayColor, smoothstep(0.05, 0.4, dayFactor));
    float goldenBand = 1.0 - abs(dayFactor - 0.22) / 0.22;
    color = mix(color, goldenColor, clamp(goldenBand, 0.0, 1.0) * GOLDEN_HOUR_STRENGTH * 0.7);

    return color * mix(1.0, 0.6, rainStrength);
}

// Warm-tinted block light, with a very light per-block-type color
// hint using mc_Entity's block ID when available.
//
// HONEST CAVEAT: this is NOT per-light-source dynamic RGB lighting.
// Real colored point lights (arbitrary color per placed light,
// correct falloff/shadowing per light) need a deferred renderer with
// a light-accumulation buffer - a genuinely separate project from
// this forward-shaded pack. This is a much cheaper approximation:
// vanilla's own block-light lightmap channel, tinted warm, with a
// couple of block-ID-based hue nudges for the most common emitters.
// It reads as "colored-ish lighting" at a glance but won't hold up
// to close scrutiny the way a real light-buffer implementation would.
vec3 tintBlockLight(vec3 lightmapColor, float blockLight, float blockId) {
#if COLORED_LIGHT_HINTS == 1
    vec3 warm = vec3(1.0 + BLOCKLIGHT_WARMTH * 0.3, 1.0, 1.0 - BLOCKLIGHT_WARMTH * 0.4);

    // A couple of common IDs get a stronger, more specific hue.
    // (mc_Entity.x values depend on the block registry Iris exposes;
    // treat these as best-effort hints, not a guaranteed match - see
    // README for how to extend this table.)
    vec3 hinted = warm;
    if (abs(blockId - 50.0) < 0.5 || abs(blockId - 89.0) < 0.5) {
        // torch / glowstone-ish: brighter, slightly more orange
        hinted = vec3(1.35, 1.05, 0.65);
    } else if (abs(blockId - 10.0) < 0.5 || abs(blockId - 11.0) < 0.5) {
        // lava-ish: strong orange-red
        hinted = vec3(1.5, 0.55, 0.2);
    } else if (abs(blockId - 55.0) < 0.5) {
        // redstone wire-ish: red
        hinted = vec3(1.4, 0.35, 0.3);
    }

    return lightmapColor * mix(warm, hinted, blockLight);
#else
    return lightmapColor;
#endif
}

#endif // LIGHTING_GLSL
