#ifndef COMMON_GLSL
#define COMMON_GLSL

const float PI = 3.14159265359;

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 adjustSaturation(vec3 color, float amount) {
    float l = luminance(color);
    return mix(vec3(l), color, amount);
}

// Cheap hash-based value noise - used for clouds and rain ripples.
// No texture fetch, just a handful of ALU ops; fine to call several
// times per fragment on high-end hardware, which is this pack's
// target.
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// A few octaves of valueNoise - used for cloud shape.
float fbm(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * valueNoise(p);
        p *= 2.02;
        amplitude *= 0.5;
    }
    return value;
}

float expFog(float dist, float fogStart, float fogEnd) {
    float f = clamp((dist - fogStart) / (fogEnd - fogStart), 0.0, 1.0);
    return f * f * (3.0 - 2.0 * f);
}

#endif // COMMON_GLSL
