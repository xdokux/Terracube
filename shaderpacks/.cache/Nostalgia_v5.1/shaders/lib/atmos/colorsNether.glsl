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

#define NETHER_UseBiomeColors
#define NETHER_AmbientSaturation 1.00   //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define NETHER_AmbientRed 1.00          //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define NETHER_AmbientGreen 1.00        //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define NETHER_AmbientBlue 1.00         //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]

uniform vec3 fogColor;

flat out mat3 colorPalette;

void getColorPalette() {
    #ifdef NETHER_UseBiomeColors
    vec3 linearFog  = linearToAP1(toLinear(fogColor));
    #else
    vec3 linearFog  = vec3(1.0);
    #endif
        
        linearFog   = colorSaturation(linearFog, NETHER_AmbientSaturation);
        linearFog  *= vec3(NETHER_AmbientRed, NETHER_AmbientGreen, NETHER_AmbientBlue);
        linearFog  *= sqrt3;

    colorPalette[0] = linearFog * sqrt3;    //ambient light
    colorPalette[1] = linearFog / tau;    //sky + fog
    colorPalette[2] = blackbody(float(blocklightBaseTemp)) * blocklightIllum * blocklightBaseMult;
}