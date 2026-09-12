#ifndef CINDERLIGHT_END_LIGHTING_GLSL
#define CINDERLIGHT_END_LIGHTING_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/end_common.glsl"

#ifdef CINDERLIGHT_LIGHTING_STATE_ONLY
uniform mat4 gbufferModelViewInverse;
#endif

void getLightingState(out vec4 lightingState0, out vec4 lightingState1) {
    lightingState0 = vec4(END_AMBIENT_COLOR, 1.0);
    lightingState1 = vec4(END_COSMIC_LIGHT_DIRECTION, 1.0);
}

#ifndef CINDERLIGHT_LIGHTING_STATE_ONLY

vec2 decodeEndLightmap(vec2 lightmapCoord) {
    return saturate((lightmapCoord - vec2(0.03125)) * 1.0666667);
}

vec3 evaluateLighting(vec3 albedoLinear, vec3 normalWorld, vec3 playerPosition,
                      vec2 lightmapCoord, float receiveShadow,
                      vec4 lightingState0, vec4 lightingState1) {
    normalWorld = safeNormalize(normalWorld);
    vec2 light = decodeEndLightmap(lightmapCoord);
    float blockLight = pow(light.x, 1.18);
    float skyLight = smoothCubic(light.y);
    float hemisphere = normalWorld.y * 0.5 + 0.5;

    vec3 ambient = lightingState0.rgb * mix(0.76, 1.08, hemisphere);
    ambient *= mix(0.90, 1.08, skyLight);
    ambient += vec3(0.018, 0.012, 0.038) * (1.0 - hemisphere);

    float sourceFacing = max(dot(normalWorld, lightingState1.xyz), 0.0);
    float sourceSoftness = sourceFacing * sourceFacing * (3.0 - 2.0 * sourceFacing);
    vec3 cosmicLight = END_COSMIC_LIGHT_COLOR * (0.060 + sourceSoftness * 0.255);

    vec3 localLight = END_BLOCK_LIGHT_COLOR * blockLight * 1.48;
    localLight += vec3(0.300, 0.225, 0.540) * blockLight * blockLight * 0.34;

    float silhouette = 0.94 + 0.06 * abs(normalWorld.y);
    vec3 minimumVisibility = vec3(0.021, 0.019, 0.038);
    vec3 lighting = (ambient + cosmicLight) * silhouette + localLight + minimumVisibility;
    return albedoLinear * lighting;
}

vec3 evaluateLighting(vec3 albedoLinear, vec3 normalWorld, vec3 playerPosition,
                      vec2 lightmapCoord, float receiveShadow) {
    vec4 lightingState0;
    vec4 lightingState1;
    getLightingState(lightingState0, lightingState1);
    return evaluateLighting(albedoLinear, normalWorld, playerPosition, lightmapCoord,
                            receiveShadow, lightingState0, lightingState1);
}

#endif

#endif
