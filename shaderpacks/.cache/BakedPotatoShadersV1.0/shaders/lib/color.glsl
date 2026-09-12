#ifndef CINDERLIGHT_COLOR_GLSL
#define CINDERLIGHT_COLOR_GLSL

#include "/lib/math.glsl"

vec3 srgbToLinearFast(vec3 c) {
    return c * c;
}

vec3 linearToSrgb(vec3 c) {
    return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

vec3 applySaturation(vec3 color, float amount) {
    float luma = luminance(color);
    return mix(vec3(luma), color, amount);
}

vec3 applyWarmth(vec3 color, float amount) {
    float delta = amount - 1.0;
    return color * vec3(1.0 + 0.11 * delta, 1.0 + 0.015 * delta, 1.0 - 0.09 * delta);
}

#endif
