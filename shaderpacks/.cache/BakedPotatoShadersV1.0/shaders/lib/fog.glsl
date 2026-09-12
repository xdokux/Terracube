#ifndef CINDERLIGHT_FOG_GLSL
#define CINDERLIGHT_FOG_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/sky.glsl"
#include "/lib/world.glsl"
#include "/lib/weather.glsl"
#include "/lib/overworld_biome_fog.glsl"

uniform float far;
uniform ivec2 eyeBrightnessSmooth;
uniform int isEyeInWater;

float getEyeSkyLight() {
    return saturate(float(eyeBrightnessSmooth.y) / 240.0);
}

float getDistanceFogAmountFromDistance(float distanceToCamera) {
    float startDistance = far * 0.52;
    float endDistance = far * 0.98;
    return smoothstep(startDistance, endDistance, distanceToCamera * FOG_DENSITY);
}

float getDistanceFogAmount(vec3 playerPosition) {
    return getDistanceFogAmountFromDistance(length(playerPosition));
}

float getHeightFogAmountResolved(vec3 playerPosition, vec3 direction, float distanceToCamera) {
    float worldY = playerPosition.y + cameraPosition.y;
    float lowAltitude = saturate((78.0 - worldY) * 0.010);
    float horizonView = 1.0 - abs(direction.y);
    float distanceTerm = smoothstep(20.0, max(far * 0.82, 24.0), distanceToCamera);
    return lowAltitude * horizonView * distanceTerm * 0.34 * FOG_DENSITY;
}

float getHeightFogAmount(vec3 playerPosition) {
    float distanceToCamera = length(playerPosition);
    return getHeightFogAmountResolved(playerPosition, safeNormalize(playerPosition), distanceToCamera);
}

vec3 getAtmosphericFogColorResolved(vec3 playerPosition, vec3 direction,
                                    float eyeSkyLight, float dimensionSky,
                                    vec4 temporalState, vec4 sunState, vec3 moonDirection) {
    vec3 sunDirection = sunState.xyz;
    float timeOfDay;
    float skyTwilight;
    float twilight;
    float sunrise;
    float sunset;
    getVisibleSkyPhaseState(temporalState.x, sunDirection, timeOfDay, skyTwilight,
                            twilight, sunrise, sunset);
    float day = temporalState.y;
    float warmWindow = max(sunrise, sunset);
    float atmosphereY = clamp(direction.y, -0.46, 1.0);
    vec3 atmosphericDirection = safeNormalize(vec3(direction.x, atmosphereY, direction.z));
    vec3 atmospheric = getVisibleSkyColorResolved(atmosphericDirection, timeOfDay, day, skyTwilight,
                                                  sunDirection, moonDirection, sunrise, sunset);
    vec3 dimensionFog = max(fogColor * fogColor, vec3(0.012));
    atmospheric = mix(dimensionFog, atmospheric, dimensionSky);

    float outdoorSky = smoothstep(0.10, 0.55, eyeSkyLight);
    if (twilight > 0.0 && warmWindow > 0.0 && outdoorSky > 0.0 && dimensionSky > 0.0) {
        float horizonView = getVisibleTwilightScatter(direction);
        float sunward = getCinematicTwilightSunward(direction, sunDirection);
        vec3 twilightFog = getVisibleCinematicTwilightFogColor(direction, sunward, sunDirection.y,
                                                        sunrise, sunset);
        float twilightBlend = twilight * warmWindow * horizonView * (0.20 + 0.10 * sunward) * outdoorSky *
                              dimensionSky * (1.0 - saturate(rainStrength) * 0.75);
        atmospheric = mix(atmospheric, twilightFog, twilightBlend);
    }

    // Restrained biome colour grade on the proven fog path. Luminance matching
    // preserves the existing fog brightness; only chromatic atmosphere changes.
    vec3 biomePalette = getOverworldBiomeFogTint();
    vec3 biomeFogColor = matchBiomeFogLuminance(biomePalette, luminance(atmospheric));
    float biomeColorInfluence = outdoorSky * dimensionSky * 0.30;
    atmospheric = mix(atmospheric, biomeFogColor, biomeColorInfluence);

    float rain = saturate(rainStrength) * outdoorSky * dimensionSky;
    atmospheric = mix(atmospheric, getRainFogColor(day, fogColor), rain * 0.82);

    float lightningFlash = getWeatherLightningFlash();
    atmospheric = applyWeatherLightning(atmospheric, lightningFlash * outdoorSky, 0.84, 0.06, 0.020);

    float cave = 1.0 - smoothstep(0.06, 0.42, eyeSkyLight);
    vec3 caveFog = vec3(0.018, 0.024, 0.030) * CAVE_BRIGHTNESS;
    return mix(atmospheric, caveFog, cave * 0.86);
}

vec3 getAtmosphericFogColor(vec3 playerPosition) {
    vec4 temporalState;
    vec4 sunState;
    vec3 moonDirection;
    getAtmosphereState(temporalState, sunState, moonDirection);
    vec3 direction = safeNormalize(playerPosition);
    return getAtmosphericFogColorResolved(playerPosition, direction,
                                          getEyeSkyLight(), getDimensionSkyFactor(),
                                          temporalState, sunState, moonDirection);
}

float getCombinedFogAmount(vec3 playerPosition, vec3 direction, float distanceToCamera,
                           float eyeSkyLight, float dimensionSky) {
    float fogAmount = max(getDistanceFogAmountFromDistance(distanceToCamera),
                          getHeightFogAmountResolved(playerPosition, direction, distanceToCamera));

    if (isEyeInWater == 0) {
        // Small biome density differences affect outdoor atmospheric
        // perspective only; underwater fog and weather haze are unchanged.
        float outdoorSky = smoothstep(0.18, 0.58, eyeSkyLight) * dimensionSky;
        float biomeDensity = mix(1.0, getOverworldBiomeFogDensity(), outdoorSky);
        fogAmount = saturate(fogAmount * biomeDensity);

        float rain = saturate(rainStrength);
        if (rain > 0.0 && outdoorSky > 0.0) {
            float horizonView = 1.0 - smoothstep(0.12, 0.84, abs(direction.y));
            float hazeDistance = smoothstep(max(far * 0.28, 16.0), max(far * 0.90, 32.0), distanceToCamera);
            float rainHaze = rain * outdoorSky * hazeDistance * (0.075 + horizonView * 0.105);
            fogAmount = 1.0 - (1.0 - saturate(fogAmount)) * (1.0 - saturate(rainHaze));
        }
    } else if (isEyeInWater == 1) {
        float waterFog = smoothstep(4.0, 60.0, distanceToCamera);
        fogAmount = max(fogAmount, waterFog);
    }
    return fogAmount;
}

vec3 applyAtmosphericFogResolved(vec3 color, vec3 playerPosition, vec3 direction,
                                 float fogAmount, float eyeSkyLight, float dimensionSky,
                                 vec4 temporalState, vec4 sunState, vec3 moonDirection) {
    if (fogAmount <= 0.0) return color;

    vec3 fogTint;
    if (isEyeInWater == 1) {
        fogTint = mix(vec3(0.014, 0.070, 0.087), vec3(0.020, 0.112, 0.125), temporalState.y);
    } else {
        fogTint = getAtmosphericFogColorResolved(playerPosition, direction,
                                                 eyeSkyLight, dimensionSky,
                                                 temporalState, sunState, moonDirection);
    }
    return mix(color, fogTint, saturate(fogAmount));
}

vec3 applyAtmosphericFog(vec3 color, vec3 playerPosition,
                         vec4 temporalState, vec4 sunState, vec3 moonDirection) {
    float distanceToCamera = length(playerPosition);
    vec3 direction = safeNormalize(playerPosition);
    float eyeSkyLight = getEyeSkyLight();
    float dimensionSky = getDimensionSkyFactor();
    float fogAmount = getCombinedFogAmount(playerPosition, direction, distanceToCamera,
                                           eyeSkyLight, dimensionSky);
    return applyAtmosphericFogResolved(color, playerPosition, direction, fogAmount,
                                       eyeSkyLight, dimensionSky,
                                       temporalState, sunState, moonDirection);
}

vec3 applyAtmosphericFog(vec3 color, vec3 playerPosition) {
    float distanceToCamera = length(playerPosition);
    vec3 direction = safeNormalize(playerPosition);
    float eyeSkyLight = getEyeSkyLight();
    float dimensionSky = getDimensionSkyFactor();
    float fogAmount = getCombinedFogAmount(playerPosition, direction, distanceToCamera,
                                           eyeSkyLight, dimensionSky);
    if (fogAmount <= 0.0) return color;

    vec4 temporalState;
    vec4 sunState;
    vec3 moonDirection;
    getAtmosphereState(temporalState, sunState, moonDirection);
    return applyAtmosphericFogResolved(color, playerPosition, direction, fogAmount,
                                       eyeSkyLight, dimensionSky,
                                       temporalState, sunState, moonDirection);
}

#endif
