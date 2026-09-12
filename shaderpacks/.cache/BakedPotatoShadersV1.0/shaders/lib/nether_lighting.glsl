#ifndef CINDERLIGHT_NETHER_LIGHTING_GLSL
#define CINDERLIGHT_NETHER_LIGHTING_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/nether_common.glsl"

#ifdef CINDERLIGHT_LIGHTING_STATE_ONLY
uniform mat4 gbufferModelViewInverse;
#endif

void getLightingState(out vec4 lightingState0, out vec4 lightingState1) {
    vec4 weights = getNetherBiomeWeights();
    lightingState0 = vec4(getNetherAmbientColor(weights), weights.w);
    lightingState1 = vec4(getNetherBlockLightColor(weights), weights.x);
}

#ifndef CINDERLIGHT_LIGHTING_STATE_ONLY

vec2 decodeNetherLightmap(vec2 lightmapCoord) {
    return saturate((lightmapCoord - vec2(0.03125)) * 1.0666667);
}

vec3 evaluateLighting(vec3 albedoLinear, vec3 normalWorld, vec3 playerPosition,
                      vec2 lightmapCoord, float receiveShadow,
                      vec4 lightingState0, vec4 lightingState1) {
    normalWorld = safeNormalize(normalWorld);
    vec2 light = decodeNetherLightmap(lightmapCoord);
    float blockLight = pow(light.x, 1.14);
    float blockLight2 = blockLight * blockLight;
    float hemisphere = normalWorld.y * 0.5 + 0.5;

    vec3 ambient = lightingState0.rgb * mix(0.72, 1.05, hemisphere);
    ambient += vec3(0.072, 0.019, 0.009) * (1.0 - hemisphere) * (0.45 + lightingState0.a * 0.35);

    float lowerBounce = mix(1.16, 0.88, hemisphere);
    vec3 localLight = lightingState1.rgb * blockLight * 1.82 * lowerBounce;
    localLight += vec3(1.00, 0.620, 0.190) * blockLight2 * 0.48;

    float sideDefinition = 0.90 + 0.10 * abs(normalWorld.y);
    float minimumVisibility = 0.018 + lightingState1.a * 0.004;
    vec3 lighting = ambient * sideDefinition + localLight + vec3(minimumVisibility, minimumVisibility * 0.66, minimumVisibility * 0.48);
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
