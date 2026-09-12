#ifndef CINDERLIGHT_END_FOG_GLSL
#define CINDERLIGHT_END_FOG_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/end_common.glsl"
#include "/lib/world.glsl"

uniform float far;
uniform int isEyeInWater;

float getEndDistanceFogAmount(float distanceToCamera) {
    float startDistance = far * 0.47;
    float endDistance = far * 1.08;
    return smoothstep(startDistance, endDistance, distanceToCamera * FOG_DENSITY);
}

float getEndLayeredHaze(vec3 direction, float distanceToCamera) {
    float horizon = 1.0 - smoothstep(0.12, 0.78, abs(direction.y));
    float distanceLayer = smoothstep(max(32.0, far * 0.26), max(72.0, far * 0.92),
                                     distanceToCamera);
    return horizon * distanceLayer * 0.085;
}

float getEndOuterIslandFogAmount(vec3 playerPosition, vec3 direction,
                                 float distanceToCamera) {
    vec3 worldPosition = playerPosition + cameraPosition;
    float worldRadiusSquared = dot(worldPosition.xz, worldPosition.xz);
    float outerIslandRegion = smoothstep(672400.0, 1254400.0, worldRadiusSquared);
    if (outerIslandRegion <= 0.0) return 0.0;

    float distanceFade = smoothstep(max(48.0, far * 0.34),
                                    max(112.0, far * 0.94), distanceToCamera);
    float horizonWeight = mix(0.72, 1.0,
                              1.0 - smoothstep(0.14, 0.82, abs(direction.y)));
    return outerIslandRegion * distanceFade * horizonWeight * 0.085;
}

vec3 getEndAtmosphereColor(vec3 direction) {
    float vertical = smoothstep(0.04, 0.82, abs(direction.y));
    vec3 horizonColor = vec3(0.034, 0.022, 0.072);
    vec3 upperColor = vec3(0.008, 0.010, 0.027);
    vec3 fogTint = mix(horizonColor, upperColor, vertical);
    float cosmicGlow = getEndCosmicAtmosphericGlow(direction);
    fogTint += vec3(0.075, 0.105, 0.275) * cosmicGlow * 0.22;
    return fogTint;
}

float getEndFogAmount(vec3 direction, float distanceToCamera) {
    float distanceFog = getEndDistanceFogAmount(distanceToCamera);
    float layeredHaze = getEndLayeredHaze(direction, distanceToCamera);
    float fogAmount = 1.0 - (1.0 - saturate(distanceFog)) * (1.0 - saturate(layeredHaze));

    if (isEyeInWater == 1) {
        fogAmount = max(fogAmount, smoothstep(4.0, 48.0, distanceToCamera));
    } else if (isEyeInWater == 2) {
        fogAmount = max(fogAmount, smoothstep(0.35, 7.0, distanceToCamera));
    }
    return saturate(fogAmount);
}

vec3 applyAtmosphericFog(vec3 color, vec3 playerPosition) {
    float distanceToCamera = length(playerPosition);
    if (distanceToCamera <= 0.001) return color;
    vec3 direction = playerPosition / distanceToCamera;
    float fogAmount = getEndFogAmount(direction, distanceToCamera);
    if (isEyeInWater == 0) {
        float outerIslandFog = getEndOuterIslandFogAmount(playerPosition, direction,
                                                           distanceToCamera);
        fogAmount = 1.0 - (1.0 - fogAmount) * (1.0 - outerIslandFog);
    }
    if (fogAmount <= 0.0) return color;

    vec3 fogTint;
    if (isEyeInWater == 1) {
        fogTint = vec3(0.010, 0.026, 0.054);
    } else if (isEyeInWater == 2) {
        fogTint = vec3(0.740, 0.145, 0.020);
    } else {
        fogTint = getEndAtmosphereColor(direction);
    }
    return mix(color, fogTint, fogAmount);
}

#endif
