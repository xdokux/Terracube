#ifndef WATER_GLSL
#define WATER_GLSL

#include "settings.glsl"
#include "common.glsl"

float waterWaveHeight(vec2 worldPosXZ, float time) {
    float t = time * WATER_WAVE_SPEED;
    float wave1 = sin(worldPosXZ.x * 0.6 + worldPosXZ.y * 0.4 + t * 1.2);
    float wave2 = sin(worldPosXZ.x * 0.35 - worldPosXZ.y * 0.5 + t * 0.8 + 1.7);
    return (wave1 * 0.6 + wave2 * 0.4) * WATER_WAVE_HEIGHT;
}

// Rain-ripple normal perturbation for water surfaces - concentric
// ring pattern per raindrop "cell", faded in by rainStrength.
vec2 rainRippleNormal(vec2 worldPosXZ, float time, float rainStrength) {
#if RAIN_RIPPLES == 1
    vec2 cell = floor(worldPosXZ * 2.0);
    float cellSeed = hash12(cell);
    float dropTime = fract(time * 0.6 + cellSeed * 10.0);
    vec2 cellCenter = (cell + 0.5) / 2.0;
    float d = length(worldPosXZ - cellCenter);

    float ring = sin((d - dropTime * 1.6) * 18.0) * exp(-d * 3.0) * exp(-dropTime * 2.5);
    vec2 dir = normalize(worldPosXZ - cellCenter + 0.0001);
    return dir * ring * 0.04 * rainStrength;
#else
    return vec2(0.0);
#endif
}

// Puddle mask on non-water horizontal surfaces (top-facing terrain),
// using a low-frequency noise so puddles form as patches rather than
// a uniform sheen across every block. Faded in by rainStrength.
float puddleMask(vec2 worldPosXZ, vec3 normal, float rainStrength) {
#if PUDDLES == 1
    float upFacing = smoothstep(0.7, 0.95, normal.y);
    float patches = fbm(worldPosXZ * 0.08, 3);
    float mask = smoothstep(1.0 - PUDDLE_COVERAGE, 1.0 - PUDDLE_COVERAGE + 0.15, patches);
    return mask * upFacing * rainStrength;
#else
    return 0.0;
#endif
}

#endif // WATER_GLSL
