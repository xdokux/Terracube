#ifndef CINDERLIGHT_WATER_WAVES_GLSL
#define CINDERLIGHT_WATER_WAVES_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/world.glsl"

float getWaterWaveHeight(vec2 worldXZ) {
#if WATER_QUALITY == 0
    return sin(worldXZ.x * 0.19 + worldXZ.y * 0.16 + frameTimeCounter * 0.82) * 0.018;
#else
    float waveA = sin(worldXZ.x * 0.18 + worldXZ.y * 0.13 + frameTimeCounter * 0.88) * 0.024;
    float waveB = sin(worldXZ.x * -0.11 + worldXZ.y * 0.23 + frameTimeCounter * 0.61) * 0.016;
#if WATER_QUALITY == 2
    float waveC = sin(worldXZ.x * 0.31 + worldXZ.y * -0.07 + frameTimeCounter * 1.13) * 0.008;
    return waveA + waveB + waveC;
#else
    return waveA + waveB;
#endif
#endif
}

vec3 getWaterNormal(vec2 worldXZ) {
#if WATER_QUALITY == 0
    float phase = worldXZ.x * 0.19 + worldXZ.y * 0.16 + frameTimeCounter * 0.82;
    float derivative = cos(phase) * 0.018;
    return safeNormalize(vec3(-derivative * 0.19 * 1.45, 1.0, -derivative * 0.16 * 1.45));
#else
    float phaseA = worldXZ.x * 0.18 + worldXZ.y * 0.13 + frameTimeCounter * 0.88;
    float phaseB = worldXZ.x * -0.11 + worldXZ.y * 0.23 + frameTimeCounter * 0.61;
    float dx = cos(phaseA) * 0.024 * 0.18 + cos(phaseB) * 0.016 * -0.11;
    float dz = cos(phaseA) * 0.024 * 0.13 + cos(phaseB) * 0.016 * 0.23;
#if WATER_QUALITY == 2
    float phaseC = worldXZ.x * 0.31 + worldXZ.y * -0.07 + frameTimeCounter * 1.13;
    dx += cos(phaseC) * 0.008 * 0.31;
    dz += cos(phaseC) * 0.008 * -0.07;
#endif
    return safeNormalize(vec3(-dx * 1.65, 1.0, -dz * 1.65));
#endif
}

#endif
