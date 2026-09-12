#ifndef CINDERLIGHT_OVERWORLD_WATER_WAVES_GLSL
#define CINDERLIGHT_OVERWORLD_WATER_WAVES_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/world.glsl"

// Overworld-only calm-water displacement. This file is deliberately standalone:
// the reflection pass consumes only the resolved surface normal written by the
// water gbuffer and has no dependency on these wave functions.
float getOverworldWaterWaveHeight(vec2 worldXZ) {
#if WATER_QUALITY == 0
    float phaseA = dot(worldXZ, vec2(0.164, 0.113)) + frameTimeCounter * 0.31;
    return sin(phaseA) * 0.012;
#else
    float phaseA = dot(worldXZ, vec2( 0.164,  0.113)) + frameTimeCounter * 0.31;
    float phaseB = dot(worldXZ, vec2(-0.091,  0.207)) - frameTimeCounter * 0.22;
    float phaseC = dot(worldXZ, vec2( 0.273, -0.047)) + frameTimeCounter * 0.17;

    float height = sin(phaseA) * 0.0115;
    height += sin(phaseB + 1.73) * 0.0070;
    height += sin(phaseC + 4.11) * 0.0035;
#if WATER_QUALITY == 2
    float phaseD = dot(worldXZ, vec2(-0.137, -0.169)) - frameTimeCounter * 0.13;
    height += sin(phaseD + 2.37) * 0.0025;
#endif
    return height;
#endif
}

vec3 getOverworldWaterNormal(vec2 worldXZ) {
#if WATER_QUALITY == 0
    float phaseA = dot(worldXZ, vec2(0.164, 0.113)) + frameTimeCounter * 0.31;
    float slope = cos(phaseA) * 0.012;
    return safeNormalize(vec3(-slope * 0.164 * 1.45, 1.0,
                              -slope * 0.113 * 1.45));
#else
    float phaseA = dot(worldXZ, vec2( 0.164,  0.113)) + frameTimeCounter * 0.31;
    float phaseB = dot(worldXZ, vec2(-0.091,  0.207)) - frameTimeCounter * 0.22;
    float phaseC = dot(worldXZ, vec2( 0.273, -0.047)) + frameTimeCounter * 0.17;

    float cosA = cos(phaseA) * 0.0115;
    float cosB = cos(phaseB + 1.73) * 0.0070;
    float cosC = cos(phaseC + 4.11) * 0.0035;

    float dx = cosA * 0.164 + cosB * -0.091 + cosC * 0.273;
    float dz = cosA * 0.113 + cosB *  0.207 + cosC * -0.047;
#if WATER_QUALITY == 2
    float phaseD = dot(worldXZ, vec2(-0.137, -0.169)) - frameTimeCounter * 0.13;
    float cosD = cos(phaseD + 2.37) * 0.0025;
    dx += cosD * -0.137;
    dz += cosD * -0.169;
#endif
    return safeNormalize(vec3(-dx * 1.55, 1.0, -dz * 1.55));
#endif
}

#endif
