#ifndef CINDERLIGHT_NETHER_MATERIALS_GLSL
#define CINDERLIGHT_NETHER_MATERIALS_GLSL

#include "/lib/math.glsl"
#include "/lib/world.glsl"

const float NETHER_MATERIAL_LAVA = 10002.0;
const float NETHER_MATERIAL_WARM_EMISSIVE = 10100.0;
const float NETHER_MATERIAL_MAGMA = 10101.0;
const float NETHER_MATERIAL_SOUL_EMISSIVE = 10102.0;

bool isNetherMaterial(float materialId, float targetId) {
    return abs(materialId - targetId) < 0.25;
}

vec3 applyNetherMaterialEmission(vec3 litColor, vec3 albedoLinear,
                                 float materialId, vec3 playerPosition) {
    vec3 worldPosition = playerPosition + cameraPosition;

    if (isNetherMaterial(materialId, NETHER_MATERIAL_LAVA)) {
        float shimmer = 0.965 + 0.035 * sin(worldPosition.x * 0.19 + worldPosition.z * 0.23 +
                                           frameTimeCounter * 2.15);
        float textureEnergy = saturate(luminance(albedoLinear) * 2.6);
        vec3 lavaEmission = albedoLinear * vec3(1.68, 1.16, 0.72) * shimmer;
        lavaEmission += vec3(1.10, 0.270, 0.026) * (0.28 + textureEnergy * 0.34);
        return max(litColor, lavaEmission);
    }

    if (isNetherMaterial(materialId, NETHER_MATERIAL_MAGMA)) {
        float warmMask = saturate((albedoLinear.r - albedoLinear.b * 0.45) * 2.4);
        vec3 magmaEmission = albedoLinear * 1.15 + vec3(0.62, 0.105, 0.012) * warmMask;
        return max(litColor, magmaEmission);
    }

    if (isNetherMaterial(materialId, NETHER_MATERIAL_WARM_EMISSIVE)) {
        float emissionMask = smoothstep(0.025, 0.42, luminance(albedoLinear));
        vec3 warmEmission = albedoLinear * 1.42 + vec3(0.42, 0.115, 0.018) * emissionMask;
        return max(litColor, warmEmission);
    }

    if (isNetherMaterial(materialId, NETHER_MATERIAL_SOUL_EMISSIVE)) {
        float emissionMask = smoothstep(0.020, 0.34, luminance(albedoLinear));
        vec3 soulEmission = albedoLinear * 1.36 + vec3(0.020, 0.360, 0.430) * emissionMask;
        return max(litColor, soulEmission);
    }

    return litColor;
}

#endif
