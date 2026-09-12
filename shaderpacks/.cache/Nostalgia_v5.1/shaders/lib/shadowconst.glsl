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

#define shadowMapDepthConst 0.2

const float shadowDistance      = 128.0;
const float shadowIntervalSize  = 2.0;

const ivec2 shadowmapSize   = ivec2(shadowMapResolution * MC_SHADOW_QUALITY);
const vec2 shadowmapPixel   = 1.0 / vec2(shadowmapSize);
const float shadowmapDepthScale = (2.0 * 256.0) / shadowMapDepthConst;
const float shadowmapPixelZ = shadowmapDepthScale / shadowmapSize.x;

const float shadowmapBias   = 0.1*(2048.0/shadowMapResolution);