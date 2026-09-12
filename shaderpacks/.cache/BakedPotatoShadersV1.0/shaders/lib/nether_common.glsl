#ifndef CINDERLIGHT_NETHER_COMMON_GLSL
#define CINDERLIGHT_NETHER_COMMON_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/world.glsl"

uniform float netherSoulSand;
uniform float netherCrimson;
uniform float netherWarped;
uniform float netherBasalt;

vec4 getNetherBiomeWeights() {
    vec4 weights = saturate(vec4(netherSoulSand, netherCrimson, netherWarped, netherBasalt));
    float total = dot(weights, vec4(1.0));
    if (total > 1.0) weights /= total;
    return weights;
}

float getNetherWastesWeight(vec4 weights) {
    return saturate(1.0 - dot(weights, vec4(1.0)));
}

vec3 blendNetherBiomeColor(vec3 wastes, vec3 soulSand, vec3 crimson,
                           vec3 warped, vec3 basalt, vec4 weights) {
    return wastes * getNetherWastesWeight(weights) +
           soulSand * weights.x + crimson * weights.y +
           warped * weights.z + basalt * weights.w;
}

vec3 getNetherAmbientColor(vec4 weights) {
    return blendNetherBiomeColor(
        vec3(0.205, 0.052, 0.022),
        vec3(0.082, 0.142, 0.166),
        vec3(0.235, 0.040, 0.024),
        vec3(0.048, 0.145, 0.142),
        vec3(0.095, 0.042, 0.027), weights);
}

vec3 getNetherBlockLightColor(vec4 weights) {
    vec3 warm = vec3(1.080, 0.385, 0.082);
    vec3 soul = vec3(0.580, 0.720, 0.760);
    return mix(warm, soul, weights.x * 0.28);
}

vec3 getNetherFogHorizonColor(vec4 weights) {
    return blendNetherBiomeColor(
        vec3(0.245, 0.041, 0.018),
        vec3(0.068, 0.170, 0.205),
        vec3(0.285, 0.030, 0.024),
        vec3(0.025, 0.160, 0.157),
        vec3(0.086, 0.081, 0.078), weights);
}

vec3 getNetherFogUpperColor(vec4 weights) {
    return blendNetherBiomeColor(
        vec3(0.100, 0.014, 0.010),
        vec3(0.028, 0.072, 0.092),
        vec3(0.125, 0.012, 0.014),
        vec3(0.012, 0.072, 0.076),
        vec3(0.028, 0.027, 0.026), weights);
}

vec3 getNetherSkyHorizonColor(vec4 weights) {
    return blendNetherBiomeColor(
        vec3(0.285, 0.038, 0.014),
        vec3(0.060, 0.190, 0.225),
        vec3(0.315, 0.020, 0.021),
        vec3(0.018, 0.175, 0.165),
        vec3(0.190, 0.050, 0.026), weights);
}

vec3 getNetherSkyZenithColor(vec4 weights) {
    return blendNetherBiomeColor(
        vec3(0.050, 0.005, 0.006),
        vec3(0.010, 0.035, 0.050),
        vec3(0.070, 0.004, 0.009),
        vec3(0.004, 0.042, 0.048),
        vec3(0.025, 0.006, 0.008), weights);
}

float getNetherFogDensity(vec4 weights) {
    return getNetherWastesWeight(weights) * 0.98 + weights.x * 1.05 +
           weights.y * 1.00 + weights.z * 0.98 + weights.w * 1.26;
}

float getNetherAshAmount(vec4 weights) {
    return saturate(0.30 + weights.w * 0.58 + weights.x * 0.10 - weights.z * 0.08);
}

float netherHash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float netherValueNoise(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    local = local * local * (3.0 - 2.0 * local);
    float a = netherHash12(cell);
    float b = netherHash12(cell + vec2(1.0, 0.0));
    float c = netherHash12(cell + vec2(0.0, 1.0));
    float d = netherHash12(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

#endif
