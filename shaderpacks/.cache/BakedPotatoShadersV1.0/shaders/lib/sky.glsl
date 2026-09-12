#ifndef CINDERLIGHT_SKY_GLSL
#define CINDERLIGHT_SKY_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/time.glsl"

uniform vec3 fogColor;

// Smooth absolute elevation around y = 0.0. This preserves the existing
// horizon ranges while removing the derivative cusp that produced a visible
// horizontal transition during sunrise and sunset.
float getFeatheredHorizonElevation(vec3 direction) {
    const float horizonFeather = 0.0125;
    return max(sqrt(direction.y * direction.y + horizonFeather * horizonFeather) - horizonFeather, 0.0);
}

// Signed atmospheric profiles used only by the visible sunrise/sunset sky and
// its matching fog. They fade continuously above and below the horizon and do
// not contain the abs(y) cusp responsible for the straight horizontal band.
float getVisibleTwilightScatter(vec3 direction) {
    float lowerFade = smoothstep(-0.46, -0.055, direction.y);
    float upperFade = 1.0 - smoothstep(0.035, 0.92, direction.y);
    return saturate(lowerFade * upperFade);
}

float getVisibleTwilightCore(vec3 direction) {
    float lowerFade = smoothstep(-0.28, -0.015, direction.y);
    float upperFade = 1.0 - smoothstep(0.015, 0.46, direction.y);
    return saturate(lowerFade * upperFade);
}

float getTwilightHorizonSunward(vec3 direction, vec3 sunDirection) {
    vec2 viewAzimuth = normalize(direction.xz + vec2(1.0e-5));
    vec2 sunAzimuth = normalize(sunDirection.xz + vec2(1.0e-5));
    return saturate(dot(viewAzimuth, sunAzimuth) * 0.5 + 0.5);
}

float getTwilightHorizonSunward(vec3 direction) {
    return getTwilightHorizonSunward(direction, getSunDirection());
}

vec3 getTwilightHorizonColor(float sunward) {
    vec3 softPink = vec3(0.82, 0.30, 0.27);
    vec3 peach = vec3(1.00, 0.50, 0.27);
    vec3 warmYellow = vec3(1.00, 0.70, 0.30);
    vec3 orange = vec3(1.00, 0.27, 0.07);
    vec3 tint = mix(softPink, peach, smoothstep(0.05, 0.58, sunward));
    tint = mix(tint, warmYellow, smoothstep(0.52, 0.82, sunward));
    return mix(tint, orange, smoothstep(0.84, 1.0, sunward) * 0.68);
}

vec3 getTwilightAtmosphereColor(vec3 direction, vec3 sunDirection) {
    direction = safeNormalize(direction);
    float sunward = getTwilightHorizonSunward(direction, sunDirection);
    float elevation = saturate(getFeatheredHorizonElevation(direction) * 2.35);

    vec3 lowerFar = vec3(0.58, 0.29, 0.32);
    vec3 lowerSun = vec3(1.00, 0.56, 0.27);
    vec3 upperFar = vec3(0.22, 0.20, 0.36);
    vec3 upperSun = vec3(0.48, 0.30, 0.40);

    vec3 lower = mix(lowerFar, lowerSun, smoothstep(0.18, 0.92, sunward));
    vec3 upper = mix(upperFar, upperSun, smoothstep(0.12, 0.88, sunward));
    return mix(lower, upper, smoothstep(0.08, 0.88, elevation));
}

vec3 getTwilightAtmosphereColor(vec3 direction) {
    return getTwilightAtmosphereColor(direction, getSunDirection());
}

float getTwilightAtmosphereAmount(vec3 direction, float twilight) {
    direction = safeNormalize(direction);
    float elevation = getFeatheredHorizonElevation(direction);
    float lowerBand = 1.0 - smoothstep(0.015, 0.22, elevation);
    float upperBand = 1.0 - smoothstep(0.07, 0.52, elevation);
    float weatherFade = 1.0 - saturate(rainStrength) * 0.75;
    return smoothCubic(twilight) * (lowerBand * 0.32 + upperBand * 0.22) * weatherFade;
}

float getTwilightAtmosphereAmount(vec3 direction) {
    return getTwilightAtmosphereAmount(direction, getTwilightAmount());
}

float getCinematicTwilightPhase(float sunHeight) {
    return smoothCubic(1.0 - smoothstep(0.025, 0.30, abs(sunHeight)));
}

float getCinematicTwilightSunward(vec3 direction, vec3 sunDirection) {
    vec2 viewAzimuth = normalize(direction.xz + vec2(1.0e-5));
    vec2 sunAzimuth = normalize(sunDirection.xz + vec2(1.0e-5));
    return saturate(dot(viewAzimuth, sunAzimuth) * 0.5 + 0.5);
}

float getPhaseInterpolation(float value, float startValue, float endValue) {
    return smoothCubic(saturate((value - startValue) / (endValue - startValue)));
}

// Visible-sky timing remap only. It preserves every existing palette value and
// interpolation curve while compressing the real-time sunrise/sunset windows.
// Lighting, water, and other non-fog systems continue to use the original timeline.
float getVisibleSkyTransitionTime(float timeOfDay) {
    // Sunrise: keep deep night longer, then run the original blue-hour and
    // warm-rise curves through shorter real-time windows.
    if (timeOfDay < 0.0415) {
        return mix(0.000, 0.090, timeOfDay / 0.0415);
    } else if (timeOfDay < 0.250) {
        return mix(0.090, 0.250, (timeOfDay - 0.0415) / (0.250 - 0.0415));
    } else if (timeOfDay < 0.420) {
        return timeOfDay;
    }

    // Sunset: hold the afternoon palette until later, then compress the
    // original sunset and blue-hour curves so normal night is reached by
    // Minecraft's /time set night point (13000 ticks).
    if (timeOfDay < 0.445) {
        return 0.420;
    } else if (timeOfDay < 0.500) {
        return mix(0.420, 0.505, (timeOfDay - 0.445) / (0.500 - 0.445));
    } else if (timeOfDay < 0.525) {
        return mix(0.505, 0.575, (timeOfDay - 0.500) / (0.525 - 0.500));
    } else if (timeOfDay < 0.5415) {
        return mix(0.575, 0.660, (timeOfDay - 0.525) / (0.5415 - 0.525));
    } else if (timeOfDay < 0.750) {
        return mix(0.660, 0.750, (timeOfDay - 0.5415) / (0.750 - 0.5415));
    } else if (timeOfDay < 0.950) {
        return mix(0.750, 0.900, (timeOfDay - 0.750) / (0.950 - 0.750));
    } else if (timeOfDay < 0.975) {
        return mix(0.900, 0.965, (timeOfDay - 0.950) / (0.975 - 0.950));
    }
    return mix(0.965, 1.000, (timeOfDay - 0.975) / (1.000 - 0.975));
}

// Shared visible-atmosphere phase state. Both the rendered sky and atmospheric
// fog consume these exact values so their sunrise, sunset, twilight, and night
// palettes cannot drift apart.
void getVisibleSkyPhaseState(float sourceTime, vec3 sunDirection,
                             out float transitionTime, out float skyTwilight,
                             out float cinematicTwilight,
                             out float sunrise, out float sunset) {
    transitionTime = getVisibleSkyTransitionTime(sourceTime);
    skyTwilight = getTwilightAmount(sunDirection);
    cinematicTwilight = getCinematicTwilightPhase(sunDirection.y);
    sunrise = getSunrisePhaseAmount(transitionTime);
    sunset = getSunsetPhaseAmount(transitionTime);
}

vec3 getTimeOfDayZenithColor(float timeOfDay) {
    vec3 dawn = vec3(0.022, 0.070, 0.205);
    vec3 sunrise = vec3(0.090, 0.145, 0.330);
    vec3 morning = vec3(0.026, 0.205, 0.585);
    vec3 noon = vec3(0.018, 0.145, 0.505);
    vec3 afternoon = vec3(0.036, 0.170, 0.485);
    vec3 sunset = vec3(0.115, 0.080, 0.245);
    vec3 twilight = vec3(0.052, 0.040, 0.145);
    vec3 night = vec3(0.006, 0.014, 0.042);
    vec3 midnight = vec3(0.0025, 0.0065, 0.022);

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

vec3 getTimeOfDayHorizonColor(float timeOfDay) {
    vec3 dawn = vec3(0.150, 0.250, 0.445);
    vec3 sunrise = vec3(0.900, 0.260, 0.065);
    vec3 morning = vec3(0.420, 0.660, 0.900);
    vec3 noon = vec3(0.315, 0.585, 0.860);
    vec3 afternoon = vec3(0.415, 0.610, 0.825);
    vec3 sunset = vec3(0.920, 0.165, 0.035);
    vec3 twilight = vec3(0.390, 0.085, 0.190);
    vec3 night = vec3(0.024, 0.040, 0.080);
    vec3 midnight = vec3(0.012, 0.022, 0.052);

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

vec3 getSunDiscColor(float timeOfDay, float sunrise, float sunset, vec3 sunDirection) {
    float lowSun = max(sunrise, sunset);
    vec3 sunriseColor = vec3(1.000, 0.520, 0.175);
    vec3 sunsetColor = vec3(1.000, 0.365, 0.105);
    vec3 lowSunColor = mix(sunriseColor, sunsetColor, sunset / max(sunrise + sunset, 1.0e-4));
    vec3 daytimeColor = vec3(1.000, 0.890, 0.655);
    float sunElevation = smoothstep(-0.035, 0.440, sunDirection.y);
    vec3 sunColor = mix(lowSunColor, daytimeColor, sunElevation);
    float afternoonWarmth = smoothstep(0.300, 0.460, timeOfDay) * (1.0 - smoothstep(0.460, 0.520, timeOfDay));
    return mix(sunColor, vec3(1.000, 0.780, 0.500), afternoonWarmth * 0.18 * (1.0 - lowSun));
}

vec3 getSunDiscColor() {
    float timeOfDay = getTimeOfDayNormalized();
    return getSunDiscColor(timeOfDay, getSunrisePhaseAmount(timeOfDay),
                           getSunsetPhaseAmount(timeOfDay), getSunDirection());
}

vec3 getCinematicTwilightColor(vec3 direction, float sunward, float sunHeight,
                               float sunrise, float sunset) {
    float elevation = saturate(abs(direction.y) * 1.55);
    float sunLobe = smoothstep(0.12, 0.94, sunward);
    float antiSunLobe = smoothstep(0.52, 1.0, 1.0 - sunward);
    float sunBelowHorizon = 1.0 - smoothstep(-0.075, 0.095, sunHeight);
    float sunsetBlend = sunset / max(sunrise + sunset, 1.0e-4);

    vec3 sunriseFar = vec3(0.780, 0.205, 0.075);
    vec3 sunriseSun = vec3(1.000, 0.610, 0.205);
    vec3 sunsetFar = vec3(0.735, 0.095, 0.038);
    vec3 sunsetSun = vec3(1.000, 0.355, 0.075);
    vec3 lowerFar = mix(sunriseFar, sunsetFar, sunsetBlend);
    vec3 lowerSun = mix(sunriseSun, sunsetSun, sunsetBlend);
    vec3 lower = mix(lowerFar, lowerSun, sunLobe);
    lower = mix(lower, vec3(0.610, 0.055, 0.050), antiSunLobe * sunsetBlend * (0.12 + sunBelowHorizon * 0.16));

    vec3 sunriseMiddle = vec3(0.975, 0.470, 0.275);
    vec3 sunsetMiddle = vec3(0.890, 0.225, 0.205);
    vec3 middle = mix(sunriseMiddle, sunsetMiddle, sunsetBlend);
    middle = mix(middle, vec3(1.000, 0.600, 0.285), sunLobe * (0.44 - sunsetBlend * 0.12));

    vec3 sunriseUpper = vec3(0.300, 0.235, 0.455);
    vec3 sunsetUpper = vec3(0.265, 0.105, 0.345);
    vec3 upper = mix(sunriseUpper, sunsetUpper, sunsetBlend);
    upper = mix(upper, vec3(0.430, 0.150, 0.405), antiSunLobe * sunsetBlend * 0.22);

    vec3 color = mix(lower, middle, smoothstep(0.045, 0.310, elevation));
    return mix(color, upper, smoothstep(0.285, 0.900, elevation));
}

vec3 getCinematicTwilightColor(vec3 direction, float sunward, float sunHeight) {
    float timeOfDay = getTimeOfDayNormalized();
    return getCinematicTwilightColor(direction, sunward, sunHeight,
                                     getSunrisePhaseAmount(timeOfDay),
                                     getSunsetPhaseAmount(timeOfDay));
}

float getCinematicTwilightAmount(vec3 direction, float sunward, float twilight) {
    float elevation = getFeatheredHorizonElevation(direction);
    float horizonCore = 1.0 - smoothstep(0.004, 0.135, elevation);
    float lowerAtmosphere = 1.0 - smoothstep(0.055, 0.355, elevation);
    float upperTransition = 1.0 - smoothstep(0.190, 0.640, elevation);
    float sunBoost = smoothstep(0.10, 0.96, sunward);
    float weatherFade = 1.0 - saturate(rainStrength) * 0.75;
    float atmosphere = horizonCore * 0.48 + lowerAtmosphere * 0.32 + upperTransition * 0.12;
    atmosphere += (horizonCore * 0.08 + lowerAtmosphere * 0.05) * sunBoost;
    return saturate(twilight * atmosphere * weatherFade);
}

vec3 getCinematicTwilightFogColor(vec3 direction, float sunward, float sunHeight,
                                  float sunrise, float sunset) {
    float sunsetBlend = sunset / max(sunrise + sunset, 1.0e-4);
    vec3 sunriseHaze = mix(vec3(0.720, 0.230, 0.105), vec3(1.000, 0.565, 0.200),
                           smoothstep(0.08, 0.92, sunward));
    vec3 sunsetHaze = mix(vec3(0.665, 0.105, 0.060), vec3(1.000, 0.365, 0.105),
                          smoothstep(0.08, 0.92, sunward));
    vec3 fullHorizonHaze = mix(sunriseHaze, sunsetHaze, sunsetBlend);
    vec3 atmosphericColor = mix(fullHorizonHaze,
                                getCinematicTwilightColor(direction, sunward, sunHeight,
                                                          sunrise, sunset), 0.50);
    float brightness = luminance(atmosphericColor);
    return mix(atmosphericColor, vec3(brightness), 0.055);
}

vec3 getCinematicTwilightFogColor(vec3 direction, float sunward, float sunHeight) {
    float timeOfDay = getTimeOfDayNormalized();
    return getCinematicTwilightFogColor(direction, sunward, sunHeight,
                                        getSunrisePhaseAmount(timeOfDay),
                                        getSunsetPhaseAmount(timeOfDay));
}


vec3 getVisibleCinematicTwilightColor(vec3 direction, float sunward, float sunHeight,
                                      float sunrise, float sunset) {
    float elevation = smoothstep(-0.16, 0.82, direction.y);
    float sunLobe = smoothstep(0.12, 0.94, sunward);
    float antiSunLobe = smoothstep(0.52, 1.0, 1.0 - sunward);
    float sunBelowHorizon = 1.0 - smoothstep(-0.075, 0.095, sunHeight);
    float sunsetBlend = sunset / max(sunrise + sunset, 1.0e-4);

    vec3 sunriseFar = vec3(0.780, 0.205, 0.075);
    vec3 sunriseSun = vec3(1.000, 0.610, 0.205);
    vec3 sunsetFar = vec3(0.735, 0.095, 0.038);
    vec3 sunsetSun = vec3(1.000, 0.355, 0.075);
    vec3 lowerFar = mix(sunriseFar, sunsetFar, sunsetBlend);
    vec3 lowerSun = mix(sunriseSun, sunsetSun, sunsetBlend);
    vec3 lower = mix(lowerFar, lowerSun, sunLobe);
    lower = mix(lower, vec3(0.610, 0.055, 0.050), antiSunLobe * sunsetBlend * (0.12 + sunBelowHorizon * 0.16));

    vec3 sunriseMiddle = vec3(0.975, 0.470, 0.275);
    vec3 sunsetMiddle = vec3(0.890, 0.225, 0.205);
    vec3 middle = mix(sunriseMiddle, sunsetMiddle, sunsetBlend);
    middle = mix(middle, vec3(1.000, 0.600, 0.285), sunLobe * (0.44 - sunsetBlend * 0.12));

    vec3 sunriseUpper = vec3(0.300, 0.235, 0.455);
    vec3 sunsetUpper = vec3(0.265, 0.105, 0.345);
    vec3 upper = mix(sunriseUpper, sunsetUpper, sunsetBlend);
    upper = mix(upper, vec3(0.430, 0.150, 0.405), antiSunLobe * sunsetBlend * 0.22);

    vec3 color = mix(lower, middle, smoothstep(0.045, 0.310, elevation));
    return mix(color, upper, smoothstep(0.285, 0.900, elevation));
}

float getVisibleCinematicTwilightAmount(vec3 direction, float sunward, float twilight) {
    float broadScatter = getVisibleTwilightScatter(direction);
    float innerGlow = getVisibleTwilightCore(direction);
    float sunBoost = smoothstep(0.10, 0.96, sunward);
    float sideSoftness = mix(0.70, 1.0, sunBoost);
    float weatherFade = 1.0 - saturate(rainStrength) * 0.75;
    float atmosphere = (broadScatter * 0.58 + innerGlow * 0.20) * sideSoftness;
    return saturate(twilight * atmosphere * weatherFade);
}

vec3 getVisibleCinematicTwilightFogColor(vec3 direction, float sunward, float sunHeight,
                                         float sunrise, float sunset) {
    float sunsetBlend = sunset / max(sunrise + sunset, 1.0e-4);
    vec3 sunriseHaze = mix(vec3(0.720, 0.230, 0.105), vec3(1.000, 0.565, 0.200),
                           smoothstep(0.08, 0.92, sunward));
    vec3 sunsetHaze = mix(vec3(0.665, 0.105, 0.060), vec3(1.000, 0.365, 0.105),
                          smoothstep(0.08, 0.92, sunward));
    vec3 fullHorizonHaze = mix(sunriseHaze, sunsetHaze, sunsetBlend);
    vec3 atmosphericColor = mix(fullHorizonHaze,
                                getVisibleCinematicTwilightColor(direction, sunward, sunHeight,
                                                                 sunrise, sunset), 0.50);
    float brightness = luminance(atmosphericColor);
    return mix(atmosphericColor, vec3(brightness), 0.055);
}

vec3 getSkyColorPrepared(vec3 direction, float day, float night,
                         vec3 sunDirection, vec3 moonDirection,
                         float sunrise, float sunset,
                         vec3 phaseZenith, vec3 phaseHorizon,
                         float gradientPower, float warmPhase,
                         float sunVisibility, vec3 sunColor,
                         float rain, vec3 rainSky) {
    float up = saturate(direction.y);
    float horizon = 1.0 - smoothstep(-0.02, 0.38, getFeatheredHorizonElevation(direction));
    vec3 sky = mix(phaseHorizon, phaseZenith, pow(up, gradientPower));

    if (warmPhase > 0.0 && horizon > 0.0) {
        float facing = getSunriseSunsetFacing(direction, sunDirection);
        vec3 horizonScatter = getCinematicTwilightColor(direction, facing, sunDirection.y,
                                                        sunrise, sunset);
        float fullHorizonScatter = warmPhase * horizon * (0.10 + 0.10 * facing);
        sky = mix(sky, horizonScatter, fullHorizonScatter * (1.0 - rain * 0.75));
    }

    if (sunVisibility > 0.0) {
        float sunAlignment = max(dot(direction, sunDirection), 0.0);
        if (sunAlignment > 0.86) {
            float sunHalo = smoothstep(0.86, 1.0, sunAlignment);
            sunHalo *= sunHalo;
            float sunCoreGlow = smoothstep(0.982, 1.0, sunAlignment);
            sky += sunColor * sunHalo * sunVisibility * (0.030 + day * 0.028 + warmPhase * 0.060);
            sky += sunColor * sunCoreGlow * sunVisibility * (0.022 + day * 0.025);
        }
    }

    if (night > 0.0) {
        float moonAlignment = max(dot(direction, moonDirection), 0.0);
        if (moonAlignment > 0.0) {
            float moonGlow = pow96(moonAlignment) * night;
            sky += vec3(0.14, 0.19, 0.32) * moonGlow * 0.18;
        }
    }

    float belowHorizon = 1.0 - smoothstep(-0.22, 0.02, direction.y);
    vec3 lowerSky = phaseHorizon * mix(0.32, 0.54, day);
    sky = mix(sky, lowerSky, belowHorizon);
    sky = mix(sky, rainSky, rain * 0.72);
    return max(sky, vec3(0.0));
}

vec3 getSkyColorResolved(vec3 direction, float timeOfDay, float day, float twilight,
                         vec3 sunDirection, vec3 moonDirection,
                         float sunrise, float sunset) {
    float night = 1.0 - day;
    vec3 phaseZenith = getTimeOfDayZenithColor(timeOfDay);
    vec3 phaseHorizon = getTimeOfDayHorizonColor(timeOfDay);
    float gradientPower = mix(0.64, 0.46, day);
    gradientPower = mix(gradientPower, 0.54, twilight * 0.72);
    float warmPhase = max(sunrise, sunset);
    float sunVisibility = smoothstep(-0.075, 0.025, sunDirection.y);
    vec3 sunColor = vec3(0.0);
    if (sunVisibility > 0.0) sunColor = getSunDiscColor(timeOfDay, sunrise, sunset, sunDirection);
    float rain = saturate(rainStrength);
    vec3 rainSky = mix(vec3(0.055, 0.075, 0.095), max(fogColor * fogColor, vec3(0.025)), day * 0.65 + 0.15);
    return getSkyColorPrepared(direction, day, night, sunDirection, moonDirection,
                               sunrise, sunset, phaseZenith, phaseHorizon,
                               gradientPower, warmPhase, sunVisibility, sunColor,
                               rain, rainSky);
}


vec3 getVisibleSkyColorPrepared(vec3 direction, float day, float night,
                                vec3 sunDirection, vec3 moonDirection,
                                float sunrise, float sunset,
                                vec3 phaseZenith, vec3 phaseHorizon,
                                float gradientPower, float warmPhase,
                                float sunVisibility, vec3 sunColor,
                                float rain, vec3 rainSky) {
    float baseUp = saturate(direction.y);
    float scatteredUp = smoothstep(-0.16, 0.94, direction.y);
    float up = mix(baseUp, scatteredUp, warmPhase);
    float baseHorizon = 1.0 - smoothstep(-0.02, 0.38, getFeatheredHorizonElevation(direction));
    float horizon = mix(baseHorizon, getVisibleTwilightScatter(direction), warmPhase);
    vec3 sky = mix(phaseHorizon, phaseZenith, pow(up, gradientPower));

    if (warmPhase > 0.0 && horizon > 0.0) {
        float facing = getSunriseSunsetFacing(direction, sunDirection);
        vec3 horizonScatter = getVisibleCinematicTwilightColor(direction, facing, sunDirection.y,
                                                               sunrise, sunset);
        float fullHorizonScatter = warmPhase * horizon * (0.10 + 0.10 * facing);
        sky = mix(sky, horizonScatter, fullHorizonScatter * (1.0 - rain * 0.75));
    }

    if (sunVisibility > 0.0) {
        float sunAlignment = max(dot(direction, sunDirection), 0.0);
        if (sunAlignment > 0.86) {
            float sunHalo = smoothstep(0.86, 1.0, sunAlignment);
            sunHalo *= sunHalo;
            float sunCoreGlow = smoothstep(0.982, 1.0, sunAlignment);
            sky += sunColor * sunHalo * sunVisibility * (0.030 + day * 0.028 + warmPhase * 0.060);
            sky += sunColor * sunCoreGlow * sunVisibility * (0.022 + day * 0.025);
        }
    }

    if (night > 0.0) {
        float moonAlignment = max(dot(direction, moonDirection), 0.0);
        if (moonAlignment > 0.0) {
            float moonGlow = pow96(moonAlignment) * night;
            sky += vec3(0.14, 0.19, 0.32) * moonGlow * 0.18;
        }
    }

    float baseBelowHorizon = 1.0 - smoothstep(-0.22, 0.02, direction.y);
    float scatteredBelowHorizon = 1.0 - smoothstep(-0.52, 0.16, direction.y);
    float belowHorizon = mix(baseBelowHorizon, scatteredBelowHorizon, warmPhase);
    vec3 lowerSky = phaseHorizon * mix(0.32, 0.54, day);
    sky = mix(sky, lowerSky, belowHorizon);
    sky = mix(sky, rainSky, rain * 0.72);
    return max(sky, vec3(0.0));
}

vec3 getVisibleSkyColorResolved(vec3 direction, float timeOfDay, float day, float twilight,
                                vec3 sunDirection, vec3 moonDirection,
                                float sunrise, float sunset) {
    float night = 1.0 - day;
    vec3 phaseZenith = getTimeOfDayZenithColor(timeOfDay);
    vec3 phaseHorizon = getTimeOfDayHorizonColor(timeOfDay);
    float gradientPower = mix(0.64, 0.46, day);
    gradientPower = mix(gradientPower, 0.54, twilight * 0.72);
    float warmPhase = max(sunrise, sunset);
    float sunVisibility = smoothstep(-0.075, 0.025, sunDirection.y);
    vec3 sunColor = vec3(0.0);
    if (sunVisibility > 0.0) sunColor = getSunDiscColor(timeOfDay, sunrise, sunset, sunDirection);
    float rain = saturate(rainStrength);
    vec3 rainSky = mix(vec3(0.055, 0.075, 0.095), max(fogColor * fogColor, vec3(0.025)), day * 0.65 + 0.15);
    return getVisibleSkyColorPrepared(direction, day, night, sunDirection, moonDirection,
                                      sunrise, sunset, phaseZenith, phaseHorizon,
                                      gradientPower, warmPhase, sunVisibility, sunColor,
                                      rain, rainSky);
}

vec3 getSkyColor(vec3 direction) {
    direction = safeNormalize(direction);
    float timeOfDay = getTimeOfDayNormalized();
    vec3 sunDirection = getSunDirection();
    vec3 moonDirection = getMoonDirection();
    float day = getDayAmount(sunDirection);
    float twilight = getTwilightAmount(sunDirection);
    float sunrise = getSunrisePhaseAmount(timeOfDay);
    float sunset = getSunsetPhaseAmount(timeOfDay);
    return getSkyColorResolved(direction, timeOfDay, day, twilight, sunDirection,
                               moonDirection, sunrise, sunset);
}

vec3 getAmbientSkyColor(float timeOfDay, float day, float twilight,
                        vec3 sunDirection, vec3 moonDirection,
                        float sunrise, float sunset) {
    float night = 1.0 - day;
    vec3 phaseZenith = getTimeOfDayZenithColor(timeOfDay);
    vec3 phaseHorizon = getTimeOfDayHorizonColor(timeOfDay);
    float gradientPower = mix(0.64, 0.46, day);
    gradientPower = mix(gradientPower, 0.54, twilight * 0.72);
    float warmPhase = max(sunrise, sunset);
    float sunVisibility = smoothstep(-0.075, 0.025, sunDirection.y);
    vec3 sunColor = vec3(0.0);
    if (sunVisibility > 0.0) sunColor = getSunDiscColor(timeOfDay, sunrise, sunset, sunDirection);
    float rain = saturate(rainStrength);
    vec3 rainSky = mix(vec3(0.055, 0.075, 0.095), max(fogColor * fogColor, vec3(0.025)), day * 0.65 + 0.15);

    vec3 upper = getSkyColorPrepared(vec3(0.0, 1.0, 0.0), day, night,
                                     sunDirection, moonDirection, sunrise, sunset,
                                     phaseZenith, phaseHorizon, gradientPower,
                                     warmPhase, sunVisibility, sunColor, rain, rainSky);
    vec3 horizonDirection = safeNormalize(vec3(0.0, 0.08, 1.0));
    vec3 horizon = getSkyColorPrepared(horizonDirection, day, night,
                                       sunDirection, moonDirection, sunrise, sunset,
                                       phaseZenith, phaseHorizon, gradientPower,
                                       warmPhase, sunVisibility, sunColor, rain, rainSky);
    return mix(horizon, upper, 0.68);
}

vec3 getAmbientSkyColor() {
    float timeOfDay = getTimeOfDayNormalized();
    vec3 sunDirection = getSunDirection();
    vec3 moonDirection = getMoonDirection();
    float day = getDayAmount(sunDirection);
    return getAmbientSkyColor(timeOfDay, day, getTwilightAmount(sunDirection),
                              sunDirection, moonDirection,
                              getSunrisePhaseAmount(timeOfDay),
                              getSunsetPhaseAmount(timeOfDay));
}

#endif
