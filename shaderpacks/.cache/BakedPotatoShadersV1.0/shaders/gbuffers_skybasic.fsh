#version 120

#include "/lib/settings.glsl"
#include "/lib/sky.glsl"
#include "/lib/weather.glsl"
#include "/lib/overworld_stars.glsl"
#include "/lib/overworld_aurora.glsl"
#include "/lib/overworld_rainbow.glsl"

uniform float frameTimeCounter;
uniform float rainbowTimer;
uniform int worldDay;

varying vec3 vWorldDirection;

void main() {
    vec3 direction = normalize(vWorldDirection);
    float timeOfDay = getTimeOfDayNormalized();
    vec3 sunDirection = getSunDirection();
    float transitionTime;
    float skyTwilight;
    float twilight;
    float sunrise;
    float sunset;
    getVisibleSkyPhaseState(timeOfDay, sunDirection, transitionTime, skyTwilight,
                            twilight, sunrise, sunset);
    float day = getDayAmount(sunDirection);
    vec3 moonDirection = vec3(0.0);
    if (day < 1.0) moonDirection = getMoonDirection();

    vec3 sky = getVisibleSkyColorResolved(direction, transitionTime, day, skyTwilight,
                                           sunDirection, moonDirection, sunrise, sunset);
    if (twilight > 0.0) {
        float sunward = getCinematicTwilightSunward(direction, sunDirection);
        float warmWindow = max(sunrise, sunset);
        float twilightAtmosphere = getVisibleCinematicTwilightAmount(direction, sunward, twilight) * warmWindow;
        sky = mix(sky, getVisibleCinematicTwilightColor(direction, sunward, sunDirection.y,
                                                         sunrise, sunset), twilightAtmosphere);
    }

    float rain = saturate(rainStrength);
    sky = mix(sky, getRainSkyColor(direction, day, fogColor), rain * 0.88);

    float lightningFlash = getWeatherLightningFlash();
    sky = applyWeatherLightning(sky, lightningFlash, 0.88, 0.07, 0.030);

    sky += getPostRainRainbow(direction, sunDirection, rain, saturate(rainbowTimer));

    float nightVisibility = smoothstep(0.24, 0.86, 1.0 - day) *
                            smoothstep(-0.02, 0.20, direction.y);
    sky += getOverworldAurora(direction, frameTimeCounter, worldDay,
                              nightVisibility, rain, transitionTime);

    float starVisibility = smoothstep(0.18, 0.78, 1.0 - day) *
                           smoothstep(-0.02, 0.20, direction.y) *
                           (1.0 - rain * 0.85);
    if (starVisibility > 0.0) {
        sky += getOverworldProceduralStars(direction, frameTimeCounter) *
               starVisibility * 0.84;
    }


    gl_FragData[0] = vec4(sky, 1.0);
}
