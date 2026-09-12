/*
====================================================================================================

    Copyright (C) 2023 RRe36

    All Rights Reserved unless otherwise explicitly stated.


    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file
    or here: https://rre36.com/copyright-license

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

#include "/lib/util/colorspace.glsl"

uniform float wetness, rainStrength, RMoonPhaseOcclusion;

uniform vec3 skyColor;
uniform vec3 fogColor;

uniform vec4 daytime;

flat out mat4x3 lightColor;     //Sunlight, Moonlight, Skylight, Blocklight

vec3 daytimeColor(vec3 rise, vec3 noon, vec3 set, vec3 night) {
    return rise * daytime.x + noon * daytime.y + set * daytime.z + night * daytime.w;
}
vec3 daytimeColorSquared(vec3 rise, vec3 noon, vec3 set, vec3 night) {
    return rise * sqr(daytime.x) + noon * (1-sqr(1-daytime.y)) + set * sqr(daytime.z) + night * (1-sqr(1-daytime.w));
}

void getColorPalette() {
    vec3 linearFog  = toLinear(fogColor);

    lightColor[0]   = daytimeColor(
        vec3(0.79, 0.306, 0.03) * 0.70,
        vec3(1.00, 0.93, 0.72) * 1.00,
        vec3(0.79, 0.29, 0.04) * 0.70,
        vec3(0.69, 0.27, 0.04) * 0.10
        ) * 16.0;

    lightColor[0]  *= sunlightIllum * vec3(sunlightRedMult, sunlightGreenMult, sunlightBlueMult);
    lightColor[0]   = colorSaturation(lightColor[0], 1.0 - wetness * 0.75) * (1.0 - wetness * 0.75);

    lightColor[1]   = vec3(0.22, 0.33, 1.0) * 0.17 * RMoonPhaseOcclusion;
    lightColor[1]  *= moonlightIllum * vec3(moonlightRedMult, moonlightGreenMult, moonlightBlueMult);
    lightColor[1]   = colorSaturation(lightColor[1], 1.0 - wetness * 0.25);

    lightColor[2]   = daytimeColor(
        vec3(0.81, 0.80, 0.97) * 0.30,
        vec3(0.75, 0.84, 0.98) * 0.50,
        vec3(0.81, 0.80, 0.97) * 0.31,
        vec3(0.33, 0.49, 0.94) * 0.01
        ) * 1.0;

    #if (!defined ssptEnabled || defined USE_SIMPLE_SKYLIGHT)
    #ifdef SIMPLE_SKYLIGHT_APPROX
        vec3 linearSky  = srgbToPipelineColor(skyColor) * sqrt2;

        vec3 skyZenith  = daytimeColor(
            linearSky * 1.00,
            linearSky * vec3(0.97, 1.18, 1.04) * 1.15,
            linearSky * 1.00,
            vec3(0.08, 0.50, 1.00) * 0.006
        );
        lightColor[2]   = (lightColor[2] * rpi + skyZenith) / euler;
    #endif
    #endif

    lightColor[2] *= vec3(skylightRedMult, skylightGreenMult, skylightBlueMult) * skylightIllum;

    lightColor[2]   = colorSaturation(lightColor[2], 1.0 - wetness * 0.9) * (1.0 + wetness * 1.75);
    

    lightColor[3]   = blackbody(float(blocklightBaseTemp)) * blocklightIllum * blocklightBaseMult * 1.5;
}