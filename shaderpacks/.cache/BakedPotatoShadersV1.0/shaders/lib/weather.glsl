#ifndef CINDERLIGHT_WEATHER_GLSL
#define CINDERLIGHT_WEATHER_GLSL

#include "/lib/math.glsl"

#ifdef IS_IRIS
uniform float thunderStrength;
uniform vec4 lightningBoltPosition;
#endif

float getWeatherLightningFlash() {
#ifdef IS_IRIS
    return saturate(thunderStrength) * step(0.5, lightningBoltPosition.w);
#else
    return 0.0;
#endif
}

vec3 applyWeatherLightning(vec3 color, float flash, float neutralAmount, float gain, float lift) {
    flash = saturate(flash);
    float neutralLuminance = max(luminance(color), 0.0);
    vec3 lightningNeutral = vec3(neutralLuminance) * vec3(0.990, 1.010, 1.045);
    color = mix(color, lightningNeutral, flash * neutralAmount);
    return color * (1.0 + flash * gain) + vec3(1.000, 1.015, 1.050) * flash * lift;
}

vec3 getRainSkyColor(vec3 direction, float dayAmount, vec3 baseFogColor) {
    direction = safeNormalize(direction);
    float up = saturate(direction.y);
    float horizon = 1.0 - smoothstep(-0.02, 0.42, abs(direction.y));

    vec3 dayHorizon = vec3(0.190, 0.202, 0.210);
    vec3 dayZenith = vec3(0.125, 0.137, 0.150);
    vec3 nightHorizon = vec3(0.046, 0.052, 0.061);
    vec3 nightZenith = vec3(0.022, 0.027, 0.035);

    vec3 dayOvercast = mix(dayHorizon, dayZenith, pow(up, 0.52));
    vec3 nightOvercast = mix(nightHorizon, nightZenith, pow(up, 0.64));
    vec3 overcast = mix(nightOvercast, dayOvercast, dayAmount);

    float fogLuminance = clamp(luminance(max(baseFogColor * baseFogColor, vec3(0.0))), 0.035, 0.230);
    vec3 neutralFog = vec3(fogLuminance);
    overcast = mix(overcast, neutralFog, horizon * 0.22);
    return overcast;
}

vec3 getRainFogColor(float dayAmount, vec3 baseFogColor) {
    float fogLuminance = clamp(luminance(max(baseFogColor * baseFogColor, vec3(0.0))), 0.040, 0.220);
    vec3 nightFog = vec3(0.042, 0.048, 0.056);
    vec3 dayFog = vec3(0.175, 0.184, 0.190);
    vec3 rainFog = mix(nightFog, dayFog, dayAmount);
    return mix(rainFog, vec3(fogLuminance), 0.24);
}

#endif
