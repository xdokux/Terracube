#version 400 compatibility

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

/* RENDERTARGETS: 4 */
layout(location = 0) out vec4 skyCapture;

#include "/lib/head.glsl"

uniform sampler2D colortex4;

in vec2 uv;

#include "/lib/offset/gauss.glsl"

const ivec2 Viewport = ivec2(256);

float GetBlurredCloudShadows(ivec2 UV) {
    vec2 Total = vec2(0.0);

    for (uint I = 0; I < 9; ++I) {
        ivec2 Offset = kernelO_3x3[I];
        float Weight = kernelW_3x3[I];

        Total += vec2(texture(colortex4, vec2(UV + Offset) / Viewport).a * Weight, Weight);
    }
    Total.x /= max(Total.y, 1e-8);

    return saturate(Total.x);
}


void main() {
    vec2 projectionUV   = fract(uv * vec2(1.0, 2.0));

    skyCapture = textureLod(colortex4, uv, 0);

    #ifdef cloudShadowsEnabled
    skyCapture.a = GetBlurredCloudShadows(ivec2(gl_FragCoord.xy));
    #endif
}