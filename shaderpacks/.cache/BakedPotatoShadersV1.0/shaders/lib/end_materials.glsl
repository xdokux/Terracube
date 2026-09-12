#ifndef CINDERLIGHT_END_MATERIALS_GLSL
#define CINDERLIGHT_END_MATERIALS_GLSL

#include "/lib/math.glsl"

const float END_MATERIAL_CHORUS = 10200.0;
const float END_MATERIAL_ROD = 10201.0;
const float END_MATERIAL_PORTAL = 10202.0;
const int END_ENTITY_CRYSTAL = 10210;

bool isEndMaterial(float materialId, float targetId) {
    return abs(materialId - targetId) < 0.25;
}

vec3 applyEndMaterialEmission(vec3 litColor, vec3 albedoLinear, float materialId) {
    if (isEndMaterial(materialId, END_MATERIAL_CHORUS)) {
        float glowMask = smoothstep(0.018, 0.30, luminance(albedoLinear));
        vec3 chorusGlow = albedoLinear * 1.06 + vec3(0.050, 0.018, 0.105) * glowMask;
        return max(litColor, chorusGlow);
    }

    if (isEndMaterial(materialId, END_MATERIAL_ROD)) {
        float glowMask = smoothstep(0.025, 0.55, luminance(albedoLinear));
        vec3 rodGlow = albedoLinear * 1.48 + vec3(0.170, 0.195, 0.420) * glowMask;
        return max(litColor, rodGlow);
    }

    if (isEndMaterial(materialId, END_MATERIAL_PORTAL)) {
        float glowMask = smoothstep(0.015, 0.32, luminance(albedoLinear));
        vec3 portalGlow = albedoLinear * 1.55 + vec3(0.105, 0.045, 0.280) * glowMask;
        return max(litColor, portalGlow);
    }

    return litColor;
}

vec3 applyEndEntityEmission(vec3 litColor, vec3 albedoLinear, int entityIdentifier) {
    if (entityIdentifier == END_ENTITY_CRYSTAL) {
        float glowMask = smoothstep(0.020, 0.62, luminance(albedoLinear));
        vec3 crystalGlow = albedoLinear * 1.62 + vec3(0.210, 0.150, 0.510) * glowMask;
        return max(litColor, crystalGlow);
    }

    return litColor;
}

#endif
