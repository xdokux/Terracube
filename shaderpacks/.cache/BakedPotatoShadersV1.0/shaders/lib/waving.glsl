#ifndef CINDERLIGHT_WAVING_GLSL
#define CINDERLIGHT_WAVING_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/world.glsl"
#include "/lib/materials.glsl"

vec3 applyFoliageWaving(vec3 playerPosition, float materialId, float topVertexWeight) {
    vec3 worldPosition = playerPosition + cameraPosition;
    float time = frameTimeCounter;

#ifdef WAVING_PLANTS
    if (isPlantMaterial(materialId)) {
        float phaseA = worldPosition.x * 0.31 + worldPosition.z * 0.23 + time * 1.35;
        float phaseB = worldPosition.x * -0.17 + worldPosition.z * 0.37 + time * 0.91;
        float sway = sin(phaseA) * 0.030 + sin(phaseB) * 0.014;
        float gust = sin(time * 0.17 + worldPosition.x * 0.025 + worldPosition.z * 0.019) * 0.35 + 0.65;
        playerPosition.x += sway * topVertexWeight * gust;
        playerPosition.z += cos(phaseA * 0.83) * 0.018 * topVertexWeight * gust;
    }
#endif

#ifdef WAVING_LEAVES
    if (isLeafMaterial(materialId)) {
        float phase = worldPosition.x * 0.23 + worldPosition.y * 0.31 + worldPosition.z * 0.19 + time * 0.72;
        float breeze = sin(phase) * 0.012 + sin(phase * 0.57 + time * 0.31) * 0.007;
        playerPosition.xz += vec2(breeze, -breeze * 0.72);
        playerPosition.y += sin(phase * 0.61) * 0.004;
    }
#endif

    return playerPosition;
}

#endif
