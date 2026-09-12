#ifndef CINDERLIGHT_END_COMMON_GLSL
#define CINDERLIGHT_END_COMMON_GLSL

#include "/lib/math.glsl"

const vec3 END_COSMIC_LIGHT_DIRECTION = vec3(-0.6804084, 0.4202522, -0.6003603);
const vec3 END_COSMIC_GLOW_RIGHT = vec3(-0.6616216, 0.0, 0.7498379);
const vec3 END_COSMIC_GLOW_UP = vec3(0.3151210, 0.9074073, 0.2780480);

const vec3 END_AMBIENT_COLOR = vec3(0.118, 0.112, 0.188);
const vec3 END_COSMIC_LIGHT_COLOR = vec3(0.445, 0.515, 0.885);
const vec3 END_BLOCK_LIGHT_COLOR = vec3(0.505, 0.365, 0.770);

float endHash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float endHash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float endValueNoise3D(vec3 p) {
    vec3 cell = floor(p);
    vec3 local = fract(p);
    local = local * local * (3.0 - 2.0 * local);
    float n000 = endHash13(cell);
    float n100 = endHash13(cell + vec3(1.0, 0.0, 0.0));
    float n010 = endHash13(cell + vec3(0.0, 1.0, 0.0));
    float n110 = endHash13(cell + vec3(1.0, 1.0, 0.0));
    float n001 = endHash13(cell + vec3(0.0, 0.0, 1.0));
    float n101 = endHash13(cell + vec3(1.0, 0.0, 1.0));
    float n011 = endHash13(cell + vec3(0.0, 1.0, 1.0));
    float n111 = endHash13(cell + vec3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, local.x);
    float nx10 = mix(n010, n110, local.x);
    float nx01 = mix(n001, n101, local.x);
    float nx11 = mix(n011, n111, local.x);
    return mix(mix(nx00, nx10, local.y), mix(nx01, nx11, local.y), local.z);
}

vec2 endOctahedralMap(vec3 direction) {
    direction /= max(abs(direction.x) + abs(direction.y) + abs(direction.z), 1.0e-5);
    vec2 mapped = direction.xy;
    if (direction.z < 0.0) {
        vec2 signs = step(vec2(0.0), mapped) * 2.0 - 1.0;
        mapped = (vec2(1.0) - abs(mapped.yx)) * signs;
    }
    return mapped * 0.5 + 0.5;
}

vec2 getEndCosmicGlowProjection(vec3 direction) {
    float facing = dot(direction, END_COSMIC_LIGHT_DIRECTION);
    float denominator = max(facing, 0.075);
    return vec2(dot(direction, END_COSMIC_GLOW_RIGHT),
                dot(direction, END_COSMIC_GLOW_UP)) / denominator;
}

float getEndCosmicAtmosphericGlow(vec3 direction) {
    direction = safeNormalize(direction);
    float facing = dot(direction, END_COSMIC_LIGHT_DIRECTION);
    if (facing <= 0.70) return 0.0;
    vec2 projected = getEndCosmicGlowProjection(direction);
    float radius = length(projected);
    float broadGlow = 1.0 - smoothstep(0.24, 0.74, radius);
    float ringGlow = 1.0 - smoothstep(0.025, 0.145, abs(radius - 0.195));
    return saturate(broadGlow * 0.38 + ringGlow * 0.62);
}

vec3 getEndReflectionSky(vec3 direction) {
    direction = safeNormalize(direction);
    float vertical = 1.0 - smoothstep(0.10, 0.88, abs(direction.y));
    vec3 reflection = mix(vec3(0.0014, 0.0018, 0.0045),
                          vec3(0.0090, 0.0045, 0.0220), vertical);
    float cosmicGlow = getEndCosmicAtmosphericGlow(direction);
    reflection += vec3(0.150, 0.220, 0.620) * cosmicGlow * 0.34;
    return reflection;
}

#endif
