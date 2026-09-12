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

#include "/lib/head.glsl"

out vec2 uv;

flat out vec3 sunDir;
flat out vec3 moonDir;

uniform int worldTime;

flat out mat2x3 skyColors;

flat out vec3 cloudSunlight;
flat out vec3 cloudSkylight;

vec3 blackbody(float temperature) {
    return vec3(0);
}

#include "/lib/atmos/colorsDefault.glsl"

void main() {
    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
    uv          = gl_MultiTexCoord0.xy;

    // Sun Position Fix from Builderb0y
    float ang   = fract(worldTime / 24000.0 - 0.25);
        ang     = (ang + (cos(ang * pi) * -0.5 + 0.5 - ang) / 3.0) * tau;
    const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));

    sunDir      = vec3(-sin(ang), cos(ang) * sunRotationData);
    moonDir     = -sunDir;

    vec3 linearSky  = srgbToPipelineColor(skyColor) * sqrt2;

    getColorPalette();

    skyColors[0]    = daytimeColor(
        linearSky * 1.00,
        linearSky * vec3(0.97, 1.18, 1.04) * 1.15,
        linearSky * 1.00,
        vec3(0.08, 0.50, 1.00) * 0.006
    ) * vec3(skyRedMult, skyGreenMult, skyBlueMult);
    skyColors[1]    = daytimeColorSquared(
        vec3(0.65, 0.18, 0.06) * 1.25,
        vec3(0.59, 0.71, 0.96) * 2.70,
        vec3(0.65, 0.16, 0.06) * 1.2,
        vec3(0.08, 0.5, 1.00) * 0.015
    ) * vec3(skyHorRedMult, skyHorGreenMult, skyHorBlueMult);

    skyColors[0]   = colorSaturation(skyColors[0], 1.0 - wetness * 0.75) * (1.0 + wetness * 1.25);
    skyColors[1]   = colorSaturation(skyColors[1], 1.0 - wetness * 0.75) * (1.0 - wetness * 0.30);

    cloudSunlight = daytimeColorSquared(
        vec3(0.67, 0.20, 0.05) * 0.45,
        vec3(0.95, 0.90, 0.76) * 0.90,
        vec3(0.65, 0.18, 0.04) * 0.45,
        vec3(0.65, 0.14, 0.03) * 0.25
        ) * 16.0 * 0.9;

    cloudSunlight   = colorSaturation(cloudSunlight, 1.0 - wetness * 0.65) * (1.0 - wetness * 0.5);

    cloudSkylight = skyColors[0];
    cloudSkylight *= mix(vec3(1.0), vec3(1.0, 1.2, 1.4), wetness);
}