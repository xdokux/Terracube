#ifndef CINDERLIGHT_PROCEDURAL_GLSL
#define CINDERLIGHT_PROCEDURAL_GLSL

#include "/lib/math.glsl"

// Arithmetic hash avoids transcendental functions and is stable on GLSL 1.20 hardware.
float proceduralHash12(vec2 position) {
    vec3 p3 = fract(vec3(position.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float proceduralValueNoise2D(vec2 position) {
    vec2 cell = floor(position);
    vec2 local = fract(position);
    vec2 blend = local * local * (3.0 - 2.0 * local);

    float a = proceduralHash12(cell);
    float b = proceduralHash12(cell + vec2(1.0, 0.0));
    float c = proceduralHash12(cell + vec2(0.0, 1.0));
    float d = proceduralHash12(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

vec2 proceduralOctahedralMap(vec3 direction) {
    direction /= max(abs(direction.x) + abs(direction.y) + abs(direction.z), 1.0e-5);
    vec2 mapped = direction.xz;
    if (direction.y < 0.0) {
        mapped = (1.0 - abs(mapped.yx)) * sign(mapped.xy + vec2(1.0e-6));
    }
    return mapped * 0.5 + 0.5;
}

#endif
