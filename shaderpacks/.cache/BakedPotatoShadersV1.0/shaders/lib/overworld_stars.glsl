#ifndef CINDERLIGHT_OVERWORLD_STARS_GLSL
#define CINDERLIGHT_OVERWORLD_STARS_GLSL

#include "/lib/math.glsl"
#include "/lib/procedural.glsl"

vec3 getOverworldStarLayer(vec2 skyUv, float scale, float threshold,
                            float baseRadius, float seed, float animationTime,
                            float clusterBias) {
    vec2 grid = skyUv * scale;
    vec2 cell = floor(grid);
    vec2 local = fract(grid);
    float randomValue = proceduralHash12(cell + seed);
    float adjustedThreshold = threshold - clusterBias;
    if (randomValue < adjustedThreshold) return vec3(0.0);

    vec2 center = vec2(proceduralHash12(cell + seed + 13.7),
                       proceduralHash12(cell + seed + 41.3));
    float radiusVariation = mix(0.78, 1.22, proceduralHash12(cell + seed + 77.1));
    float radius = baseRadius * radiusVariation;
    float distanceToStar = length(local - center);

    float core = 1.0 - smoothstep(radius * 0.38, radius, distanceToStar);
    float softFalloff = 1.0 - smoothstep(radius, radius * 1.58, distanceToStar);
    float point = core + softFalloff * 0.095;

    float brightness = mix(0.52, 1.18, proceduralHash12(cell + seed + 19.9));
    float temperature = proceduralHash12(cell + seed + 93.6);
    vec3 neutralStar = vec3(0.955, 0.970, 1.000);
    vec3 coolStar = vec3(0.72, 0.82, 1.00);
    vec3 warmStar = vec3(1.00, 0.93, 0.80);
    vec3 temperatureTint = mix(coolStar, warmStar, temperature);
    vec3 starColor = mix(neutralStar, temperatureTint, 0.44);
    float twinkle = 0.93 + 0.07 * sin(animationTime * mix(0.42, 0.76, randomValue) + randomValue * TAU);
    return starColor * point * brightness * twinkle;
}

vec3 getOverworldProceduralStars(vec3 direction, float animationTime) {
    vec2 skyUv = proceduralOctahedralMap(direction);
    float clusterField = proceduralHash12(floor(skyUv * vec2(13.0, 9.0)) + 27.4);
    float clusterBias = smoothstep(0.70, 0.96, clusterField) * 0.0085;

    vec3 stars = vec3(0.0);
    stars += getOverworldStarLayer(skyUv, 180.0, 0.9500, 0.0320, 3.8,
                                   animationTime, clusterBias);
    stars += getOverworldStarLayer(skyUv, 305.0, 0.9650, 0.0270, 47.2,
                                   animationTime, clusterBias * 0.62);
    stars += getOverworldStarLayer(skyUv, 475.0, 0.9780, 0.0230, 109.6,
                                   animationTime, clusterBias * 0.35);
    return stars;
}

#endif
