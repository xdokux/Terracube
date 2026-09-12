#ifndef CINDERLIGHT_NETHER_FOG_GLSL
#define CINDERLIGHT_NETHER_FOG_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/nether_common.glsl"

uniform float far;
uniform int isEyeInWater;

float getNetherDistanceFogAmount(float distanceToCamera, vec4 weights) {
    float density = getNetherFogDensity(weights) * FOG_DENSITY;
    float basalt = weights.w;
    float startDistance = far * mix(0.245, 0.155, basalt);
    float endDistance = far * mix(0.940, 0.795, basalt);
    return smoothstep(startDistance, endDistance, distanceToCamera * density);
}

float getNetherCavernHaze(vec3 direction, float distanceToCamera, vec4 weights) {
    float horizon = 1.0 - smoothstep(0.10, 0.82, abs(direction.y));
    float distanceTerm = smoothstep(max(18.0, far * 0.18), max(36.0, far * 0.76), distanceToCamera);
    float amount = 0.075 + weights.w * 0.090 + weights.y * 0.025;
    return horizon * distanceTerm * amount;
}

vec3 getNetherAtmosphereColor(vec3 direction, vec4 weights) {
    float vertical = smoothstep(0.02, 0.72, abs(direction.y));
    vec3 horizonColor = getNetherFogHorizonColor(weights);
    vec3 upperColor = getNetherFogUpperColor(weights);
    vec3 fogTint = mix(horizonColor, upperColor, vertical);

    return fogTint;
}

float getNetherFogAmount(vec3 direction, float distanceToCamera, vec4 weights) {
    float fogAmount = getNetherDistanceFogAmount(distanceToCamera, weights);
    float cavernHaze = getNetherCavernHaze(direction, distanceToCamera, weights);
    fogAmount = 1.0 - (1.0 - saturate(fogAmount)) * (1.0 - saturate(cavernHaze));

    if (isEyeInWater == 1) {
        fogAmount = max(fogAmount, smoothstep(3.0, 38.0, distanceToCamera));
    } else if (isEyeInWater == 2) {
        fogAmount = max(fogAmount, smoothstep(0.35, 7.0, distanceToCamera));
    }
    return saturate(fogAmount);
}

vec3 applyAtmosphericFog(vec3 color, vec3 playerPosition) {
    float distanceToCamera = length(playerPosition);
    if (distanceToCamera <= 0.001) return color;
    vec3 direction = playerPosition / distanceToCamera;
    vec4 weights = getNetherBiomeWeights();
    float fogAmount = getNetherFogAmount(direction, distanceToCamera, weights);
    if (fogAmount <= 0.0) return color;

    vec3 fogTint;
    if (isEyeInWater == 1) {
        fogTint = vec3(0.016, 0.082, 0.091);
    } else if (isEyeInWater == 2) {
        fogTint = vec3(0.820, 0.135, 0.018);
    } else {
        fogTint = getNetherAtmosphereColor(direction, weights);
    }
    return mix(color, fogTint, fogAmount);
}

#endif
