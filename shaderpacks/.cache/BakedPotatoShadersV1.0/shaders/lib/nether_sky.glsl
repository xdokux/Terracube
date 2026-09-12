#ifndef CINDERLIGHT_NETHER_SKY_GLSL
#define CINDERLIGHT_NETHER_SKY_GLSL

#include "/lib/math.glsl"
#include "/lib/nether_common.glsl"

vec3 getNetherVolcanicSky(vec3 direction) {
    direction = safeNormalize(direction);
    vec4 weights = getNetherBiomeWeights();
    float horizon = 1.0 - smoothstep(0.02, 0.70, abs(direction.y));
    float vertical = pow(saturate(abs(direction.y)), 0.58);

    vec3 horizonColor = getNetherSkyHorizonColor(weights);
    vec3 zenithColor = getNetherSkyZenithColor(weights);
    vec3 sky = mix(horizonColor, zenithColor, vertical);

    vec2 projected = direction.xz / (abs(direction.y) + 0.34);
    vec2 smokeCoord = projected * 1.18 + vec2(frameTimeCounter * 0.0060, -frameTimeCounter * 0.0035);
    float smokeA = netherValueNoise(smokeCoord);
    float smokeB = netherValueNoise(smokeCoord * 2.07 + vec2(8.4, -5.7));
    float smoke = smoothstep(0.28, 0.82, smokeA * 0.70 + smokeB * 0.30);
    smoke *= 0.20 + horizon * 0.60;

    vec3 smokeColor = mix(zenithColor * 0.42, vec3(0.030, 0.009, 0.008), 0.58);
    sky = mix(sky, smokeColor, smoke * (0.28 + weights.w * 0.16));

    float glowingCloud = smoothstep(0.62, 0.87, smokeA) * horizon;
    vec3 cloudGlow = mix(getNetherFogHorizonColor(weights), vec3(0.420, 0.085, 0.022),
                         getNetherWastesWeight(weights) + weights.y + weights.w * 0.60);
    sky += cloudGlow * glowingCloud * 0.095;

    vec2 particleCoord = projected * vec2(25.0, 18.0) +
                         vec2(frameTimeCounter * 0.055, -frameTimeCounter * 0.083);
    vec2 particleCell = floor(particleCoord);
    vec2 particleLocal = fract(particleCoord);
    float particleRandom = netherHash12(particleCell);
    vec2 particleCenter = vec2(netherHash12(particleCell + 13.7),
                               netherHash12(particleCell + 41.3));
    vec2 particleDelta = particleLocal - particleCenter;
    float particleDistance = length(particleDelta);
    float ash = (1.0 - smoothstep(0.025, 0.105, particleDistance)) *
                step(0.965, particleRandom) * getNetherAshAmount(weights);
    sky += vec3(0.090, 0.072, 0.062) * ash * 0.45;

    return max(sky, vec3(0.0));
}

#endif
