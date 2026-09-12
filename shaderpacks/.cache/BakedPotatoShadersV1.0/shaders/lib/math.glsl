#ifndef CINDERLIGHT_MATH_GLSL
#define CINDERLIGHT_MATH_GLSL

const float PI = 3.14159265358979323846;
const float TAU = 6.28318530717958647692;

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 saturate(vec2 x) { return clamp(x, vec2(0.0), vec2(1.0)); }
vec3 saturate(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }
vec4 saturate(vec4 x) { return clamp(x, vec4(0.0), vec4(1.0)); }

float square(float x) { return x * x; }
float pow5(float x) { float x2 = x * x; return x2 * x2 * x; }
float pow96(float x) { float x2 = x * x; float x4 = x2 * x2; float x8 = x4 * x4; float x16 = x8 * x8; float x32 = x16 * x16; return (x32 * x32) * x32; }
float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

float smoothCubic(float x) {
    x = saturate(x);
    return x * x * (3.0 - 2.0 * x);
}

vec3 safeNormalize(vec3 v) {
    return v * inversesqrt(max(dot(v, v), 1.0e-8));
}

#endif
