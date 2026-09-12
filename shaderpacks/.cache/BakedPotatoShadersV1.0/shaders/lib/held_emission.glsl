#ifndef CINDERLIGHT_HELD_EMISSION_GLSL
#define CINDERLIGHT_HELD_EMISSION_GLSL

#include "/lib/math.glsl"
#include "/lib/held_light_common.glsl"

// currentRenderedItemId uses item.properties for ordinary items and
// block.properties for rendered block items. Convert both ID spaces to the
// existing held-light colour groups before evaluating emission.
int getHeldEmissionGroup(int renderedItemId) {
    if (renderedItemId >= 11001 && renderedItemId <= 11007) return renderedItemId;

    if (renderedItemId == 10100 || renderedItemId == 10101) return 11001;
    if (renderedItemId == 10102) return 11002;
    if (renderedItemId == 10201 || renderedItemId == 10300) return 11003;
    if (renderedItemId == 10301) return 11006;
    if (renderedItemId == 10302) return 11007;

    return -1;
}

float getHeldItemEmissionStrength(int itemId) {
    if (itemId == 11007) return 1.62;
    if (itemId == 11006) return 1.72;
    if (itemId == 11003) return 1.82;
    if (itemId == 11002) return 1.88;
    return 1.92;
}

vec3 getHeldItemSelfEmission(vec3 albedoLinear, int renderedItemId) {
    int itemId = getHeldEmissionGroup(renderedItemId);
    if (itemId < 0) return vec3(0.0);

    float sourceLuma = luminance(albedoLinear);
    float sourceMax = max(albedoLinear.r, max(albedoLinear.g, albedoLinear.b));
    float sourceMin = min(albedoLinear.r, min(albedoLinear.g, albedoLinear.b));
    float sourceChroma = sourceMax - sourceMin;

    float brightMask = smoothstep(0.035, 0.34, sourceLuma);
    float chromaMask = smoothstep(0.16, 0.70, sourceChroma) *
                       smoothstep(0.015, 0.11, sourceLuma);
    float emissionMask = max(brightMask, chromaMask * 0.82);

    vec3 lightColor = getHeldItemLightColor(itemId);
    vec3 emissionTint = mix(vec3(1.0), lightColor, 0.32);
    vec3 texturedEmission = albedoLinear * emissionTint * emissionMask *
                            getHeldItemEmissionStrength(itemId);

    // A restrained coloured core makes the bright source texels visibly
    // self-luminous and lets the existing bloom threshold see them, while
    // dark handles and frames remain governed by the texture-aware mask.
    float coreMask = emissionMask * smoothstep(0.10, 0.58, sourceLuma);
    vec3 coreEmission = lightColor * coreMask * 0.18;
    return texturedEmission + coreEmission;
}

#endif
