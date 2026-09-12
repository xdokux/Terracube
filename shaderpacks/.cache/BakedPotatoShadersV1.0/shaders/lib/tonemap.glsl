#ifndef CINDERLIGHT_TONEMAP_GLSL
#define CINDERLIGHT_TONEMAP_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/color.glsl"

vec3 filmicTonemap(vec3 color) {
    color *= EXPOSURE;
    vec3 numerator = color * (2.51 * color + 0.03);
    vec3 denominator = color * (2.43 * color + 0.59) + 0.14;
    return saturate(numerator / denominator);
}

vec3 finishColor(vec3 color) {
    color = applyWarmth(color, COLOR_WARMTH);
    color = applySaturation(color, SATURATION);
    color = filmicTonemap(color);
    return linearToSrgb(color);
}

#endif
