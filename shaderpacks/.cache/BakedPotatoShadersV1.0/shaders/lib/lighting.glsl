#ifndef CINDERLIGHT_LIGHTING_GLSL
#define CINDERLIGHT_LIGHTING_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/time.glsl"
#include "/lib/sky.glsl"
#include "/lib/world.glsl"

#ifndef CINDERLIGHT_LIGHTING_STATE_ONLY
#include "/lib/shadow.glsl"
#endif

vec3 getTimeOfDaySunlightColor(float timeOfDay) {
    vec3 sunrise = vec3(1.100, 0.560, 0.225);
    vec3 morning = vec3(1.055, 0.885, 0.675);
    vec3 noon = vec3(1.000, 0.955, 0.855);
    vec3 afternoon = vec3(1.040, 0.835, 0.610);
    vec3 sunset = vec3(1.115, 0.425, 0.145);
    vec3 twilight = vec3(0.830, 0.315, 0.235);

    if (timeOfDay < 0.090) {
        return mix(sunrise, morning, getPhaseInterpolation(timeOfDay, 0.000, 0.090));
    } else if (timeOfDay < 0.250) {
        return mix(morning, noon, getPhaseInterpolation(timeOfDay, 0.090, 0.250));
    } else if (timeOfDay < 0.420) {
        return mix(noon, afternoon, getPhaseInterpolation(timeOfDay, 0.250, 0.420));
    } else if (timeOfDay < 0.505) {
        return mix(afternoon, sunset, getPhaseInterpolation(timeOfDay, 0.420, 0.505));
    } else if (timeOfDay < 0.575) {
        return mix(sunset, twilight, getPhaseInterpolation(timeOfDay, 0.505, 0.575));
    } else if (timeOfDay > 0.965) {
        return mix(vec3(0.700, 0.525, 0.460), sunrise,
                   getPhaseInterpolation(timeOfDay, 0.965, 1.000));
    }
    return twilight;
}

float getTimeOfDayDirectStrength(float timeOfDay) {
    float dawn = 0.100;
    float sunrise = 0.370;
    float morning = 1.020;
    float noon = 1.350;
    float afternoon = 1.120;
    float sunset = 0.430;
    float twilight = 0.155;
    float night = 0.140;
    float midnight = 0.125;

    if (timeOfDay < 0.090) {
        return mix(sunrise, morning, getPhaseInterpolation(timeOfDay, 0.000, 0.090));
    } else if (timeOfDay < 0.250) {
        return mix(morning, noon, getPhaseInterpolation(timeOfDay, 0.090, 0.250));
    } else if (timeOfDay < 0.420) {
        return mix(noon, afternoon, getPhaseInterpolation(timeOfDay, 0.250, 0.420));
    } else if (timeOfDay < 0.505) {
        return mix(afternoon, sunset, getPhaseInterpolation(timeOfDay, 0.420, 0.505));
    } else if (timeOfDay < 0.575) {
        return mix(sunset, twilight, getPhaseInterpolation(timeOfDay, 0.505, 0.575));
    } else if (timeOfDay < 0.660) {
        return mix(twilight, night, getPhaseInterpolation(timeOfDay, 0.575, 0.660));
    } else if (timeOfDay < 0.750) {
        return mix(night, midnight, getPhaseInterpolation(timeOfDay, 0.660, 0.750));
    } else if (timeOfDay < 0.900) {
        return mix(midnight, night, getPhaseInterpolation(timeOfDay, 0.750, 0.900));
    } else if (timeOfDay < 0.965) {
        return mix(night, dawn, getPhaseInterpolation(timeOfDay, 0.900, 0.965));
    }
    return mix(dawn, sunrise, getPhaseInterpolation(timeOfDay, 0.965, 1.000));
}

vec3 getDirectLightColor(float timeOfDay, float day) {
    vec3 sunlight = getTimeOfDaySunlightColor(timeOfDay);
    vec3 moonlight = vec3(0.19, 0.25, 0.40);
    vec3 directColor = mix(moonlight, sunlight, day);
    float rain = saturate(rainStrength) * day;
    if (rain > 0.0) {
        float directLuminance = max(luminance(directColor), 0.0);
        vec3 overcastDirect = vec3(directLuminance) * vec3(0.955, 0.985, 1.035);
        directColor = mix(directColor, overcastDirect, rain * 0.94);
    }
    return directColor;
}

vec3 getDirectLightColor() {
    vec3 sunDirection = getSunDirection();
    return getDirectLightColor(getTimeOfDayNormalized(), getDayAmount(sunDirection));
}

float getDirectLightStrength(float timeOfDay) {
    float rainDimming = mix(1.0, 0.16, saturate(rainStrength));
    return getTimeOfDayDirectStrength(timeOfDay) * rainDimming;
}

float getDirectLightStrength() {
    return getDirectLightStrength(getTimeOfDayNormalized());
}

void getLightingState(out vec4 lightingState0, out vec4 lightingState1) {
    float timeOfDay = getTimeOfDayNormalized();
    vec3 sunDirection = getSunDirection();
    vec3 moonDirection = getMoonDirection();
    float day = getDayAmount(sunDirection);
    float twilight = getTwilightAmount(sunDirection);
    float sunrise = getSunrisePhaseAmount(timeOfDay);
    float sunset = getSunsetPhaseAmount(timeOfDay);
    vec3 ambientSky = getAmbientSkyColor(timeOfDay, day, twilight, sunDirection,
                                         moonDirection, sunrise, sunset);
    vec3 directRadiance = getDirectLightColor(timeOfDay, day) * getDirectLightStrength(timeOfDay);
    lightingState0 = vec4(ambientSky, day);
    lightingState1 = vec4(directRadiance, getDimensionSkyFactor());
}

#ifndef CINDERLIGHT_LIGHTING_STATE_ONLY

#include "/lib/held_light_common.glsl"

uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform int heldItemId;
uniform int heldItemId2;

vec3 getHeldLightContribution(vec3 normalWorld, vec3 playerPosition) {
    float mainStrength = saturate(float(heldBlockLightValue) * (1.0 / 15.0));
    float offStrength = saturate(float(heldBlockLightValue2) * (1.0 / 15.0));
    float strongest = max(mainStrength, offStrength);
    if (strongest <= 0.0) return vec3(0.0);

    float distanceSquared = dot(playerPosition, playerPosition);
    if (distanceSquared < 0.0625) return vec3(0.0);

    float secondary = min(mainStrength, offStrength);
    float heldStrength = saturate(strongest + secondary * 0.20);
    float radius = mix(4.5, 10.0, heldStrength);
    float radiusSquared = radius * radius;
    if (distanceSquared >= radiusSquared) return vec3(0.0);

    float inverseDistance = inversesqrt(max(distanceSquared, 1.0e-4));
    float distanceToLight = distanceSquared * inverseDistance;
    vec3 lightDirection = -playerPosition * inverseDistance;
    float surfaceFacing = max(dot(normalWorld, lightDirection), 0.0);
    float normalizedDistance = distanceToLight / radius;
    float falloff = saturate(1.0 - normalizedDistance * normalizedDistance);
    falloff = falloff * falloff;

    float colorWeight = max(mainStrength + offStrength, 1.0e-4);
    vec3 lightColor = (getHeldItemLightColor(heldItemId) * mainStrength +
                       getHeldItemLightColor(heldItemId2) * offStrength) / colorWeight;
    float diffuseWrap = 0.20 + surfaceFacing * 0.80;
    return lightColor * falloff * diffuseWrap * heldStrength * 1.18;
}

vec2 decodeLightmap(vec2 lightmapCoord) {
    return saturate((lightmapCoord - vec2(0.03125)) * 1.0666667);
}

vec3 evaluateLighting(vec3 albedoLinear, vec3 normalWorld, vec3 playerPosition,
                      vec2 lightmapCoord, float receiveShadow,
                      vec4 lightingState0, vec4 lightingState1) {
    normalWorld = safeNormalize(normalWorld);
    vec2 light = decodeLightmap(lightmapCoord);
    float blockLight = pow(light.x, 1.20);
    float dimensionSky = lightingState1.w;
    float skyLight = smoothCubic(light.y) * dimensionSky;

    vec3 lightDirection = getShadowLightDirection();
    float normalDotLight = max(dot(normalWorld, lightDirection), 0.0);
    float shadowVisibility = 1.0;
    if (receiveShadow > 0.0 && normalDotLight > 0.0 && skyLight > 0.015) {
        shadowVisibility = mix(1.0, sampleSoftShadow(playerPosition, normalDotLight, skyLight), receiveShadow);
    }

    float day = lightingState0.w;
    float hemisphere = normalWorld.y * 0.5 + 0.5;
    vec3 skyAmbient = lightingState0.xyz * mix(0.22, 0.34, day);
    vec3 groundAmbient = mix(vec3(0.020, 0.024, 0.026), vec3(0.065, 0.060, 0.050), day);
    float rain = saturate(rainStrength);
    float weatherOutdoor = rain * smoothstep(0.18, 0.72, skyLight) * dimensionSky;
    if (rain > 0.0) {
        float skyAmbientLuminance = max(luminance(skyAmbient), 0.0);
        float groundAmbientLuminance = max(luminance(groundAmbient), 0.0);
        vec3 overcastSkyAmbient = vec3(skyAmbientLuminance) * vec3(0.940, 0.985, 1.045) * 1.04;
        vec3 overcastGroundAmbient = vec3(groundAmbientLuminance) * vec3(0.955, 0.990, 1.025);
        skyAmbient = mix(skyAmbient, overcastSkyAmbient, weatherOutdoor * 0.90);
        groundAmbient = mix(groundAmbient, overcastGroundAmbient, weatherOutdoor * 0.72);
    }
    vec3 hemisphereLight = mix(groundAmbient, skyAmbient, hemisphere);
    vec3 enclosedAmbient = mix(vec3(0.030, 0.026, 0.024), vec3(0.050, 0.044, 0.038), hemisphere);
    hemisphereLight = mix(enclosedAmbient, hemisphereLight, dimensionSky);

    float caveAmount = 1.0 - smoothstep(0.06, 0.62, skyLight);
    vec3 caveAmbient = vec3(0.030, 0.034, 0.037) * CAVE_BRIGHTNESS;
    vec3 ambient = hemisphereLight * (0.20 + 0.80 * skyLight) + caveAmbient * caveAmount;
    ambient += vec3(0.026, 0.029, 0.034) * day * weatherOutdoor * skyLight;

    vec3 direct = lightingState1.xyz * normalDotLight * shadowVisibility * skyLight;
    vec3 block = vec3(1.00, 0.43, 0.15) * blockLight * (0.62 + 0.38 * (1.0 - skyLight)) * 1.80;

    float outdoorBrightness = smoothstep(0.42, 0.86, skyLight) * dimensionSky;
    float naturalExposure = mix(1.55, 1.80, day);
    vec3 naturalLighting = (ambient + direct) * mix(1.0, naturalExposure, outdoorBrightness);
    float minimumVisibility = (0.012 + caveAmount * 0.013) * CAVE_BRIGHTNESS;
    vec3 heldLight = getHeldLightContribution(normalWorld, playerPosition);
    vec3 lighting = naturalLighting + block + heldLight + vec3(minimumVisibility);
    return albedoLinear * lighting;
}

vec3 evaluateLighting(vec3 albedoLinear, vec3 normalWorld, vec3 playerPosition,
                      vec2 lightmapCoord, float receiveShadow,
                      vec4 temporalState, vec4 sunState, vec3 moonDirection) {
    float timeOfDay = temporalState.x;
    float day = temporalState.y;
    vec3 ambientSky = getAmbientSkyColor(timeOfDay, day, temporalState.z, sunState.xyz,
                                         moonDirection, temporalState.w, sunState.w);
    vec3 directRadiance = getDirectLightColor(timeOfDay, day) * getDirectLightStrength(timeOfDay);
    vec4 lightingState0 = vec4(ambientSky, day);
    vec4 lightingState1 = vec4(directRadiance, getDimensionSkyFactor());
    return evaluateLighting(albedoLinear, normalWorld, playerPosition, lightmapCoord,
                            receiveShadow, lightingState0, lightingState1);
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
