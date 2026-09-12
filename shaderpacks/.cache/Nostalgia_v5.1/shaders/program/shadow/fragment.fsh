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

layout(location = 0) out vec4 data0;
layout(location = 1) out vec4 data1;

#define shadowmapTextureMipBias 0   //[1 2 3 4]

#include "/lib/head.glsl"
#include "/lib/util/encoders.glsl"
#include "/lib/util/colorspace.glsl"
#include "/lib/shadowconst.glsl"

#define gSHADOW

in float skyOcclusion;

in vec2 uv;

in float warp;

in vec3 scenePos;
in vec3 worldPos;

in vec4 tint;

flat in int matID;

flat in vec3 normal;

uniform sampler2D gcolor;

uniform sampler2D noisetex;

uniform int blockEntityId;

uniform float frameTimeCounter;

uniform vec3 cameraPosition;
uniform vec3 lightDir;

#define FUTIL_MAT16
#include "/lib/fUtil.glsl"

/* ------ caustics ------ */

#include "/lib/util/bicubic.glsl"

const float viewDist = 0.0;

#include "/lib/atmos/waterConst.glsl"

#include "/lib/atmos/waterWaves.glsl"

vec3 waterNormal(vec3 position, float dstep, int matID) {
        dstep       = max(dstep, 0.015);

    vec2 delta;
        delta.x     = waterWaves(position + vec3( dstep, 0.0, -dstep), matID);
        delta.y     = waterWaves(position + vec3(-dstep, 0.0,  dstep), matID);
        delta      -= waterWaves(position + vec3(-dstep, 0.0, -dstep), matID);

    return normalize(vec3(-delta.x, 2.0 * dstep, -delta.y));
}

float projectedCaustic(vec3 pos, vec3 normal, vec3 lightDir) {
    vec3 dPdx   = dFdx(pos);
    vec3 dPdy   = dFdy(pos);

    float num   = dotSelf(dPdx) * dotSelf(dPdy);

    vec3 refractLight = refract(-lightDir, normal, rcp(1.33));
        dPdx   += 2.0 * dFdx(refractLight);
        dPdy   += 2.0 * dFdy(refractLight);

    float denom = dotSelf(dPdx) * dotSelf(dPdy);

    return sqrt(num * rcp(denom));
}

void main() {
    if (blockEntityId == 10201) discard;

    if (matID == 102 || matID == 103) { 
        vec3 waves      = waterNormal(worldPos, rcp(shadowMapResolution) * warp, matID);
        vec3 refractLight = refract(lightDir, waves, rcp(1.33));
        float caustic   = projectedCaustic(scenePos, waves, lightDir);
        data0           = vec4(caustic * 0.25, 1.0, 1.0, 1.0);
    } else {
        data0           = texture(gcolor, uv, -shadowmapTextureMipBias);
        if (data0.a<0.1) discard;
            data0.rgb  *= tint.rgb;

        data0.rgb       = linearToAP1Albedo(data0.rgb);
        data0.a         = sqrt(data0.a);
    }

    data1.xy    = encodeNormal(normal);
    data1.z     = pack2x8(skyOcclusion, float(matID) / 255.0);
    data1.a     = 1.0;
}