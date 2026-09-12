#ifndef COMMON_GLSL
#define COMMON_GLSL

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 adjustSaturation(vec3 color, float amount) {
    float l = luminance(color);
    return mix(vec3(l), color, amount);
}

vec3 posterize(vec3 color, float levels) {
    if (levels <= 0.0) return color;
    return floor(color * levels + 0.5) / levels;
}

#endif // COMMON_GLSL
