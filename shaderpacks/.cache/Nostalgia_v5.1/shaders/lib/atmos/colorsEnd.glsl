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

flat out mat3 colorPalette;     //Sunlight, Skylight, Blocklight

#define END_AmbientRed 1.00          //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define END_AmbientGreen 0.40        //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define END_AmbientBlue 1.00         //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]

#define END_AmbColor vec3(END_AmbientRed, END_AmbientGreen, END_AmbientBlue)

void getColorPalette() {

    colorPalette[0]   = END_AmbColor * 0.3;

    colorPalette[1]   = END_AmbColor * 0.01;

    colorPalette[2]   = blackbody(float(blocklightBaseTemp)) * blocklightIllum * blocklightBaseMult;
}