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

#include "/lib/head.glsl"
#include "/lib/util/encoders.glsl"
#include "/lib/util/colorspace.glsl"
#include "/lib/shadowconst.glsl"

#define gSHADOW

in vec2 uv;

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

uniform sampler2D noisetex;

uniform float frameTimeCounter;

uniform vec3 cameraPosition;
uniform vec3 lightDir;

uniform mat4 shadowModelView, shadowProjection;
uniform mat4 shadowModelViewInverse, shadowProjectionInverse;

#define FUTIL_MAT16
#include "/lib/fUtil.glsl"
#include "/lib/light/warp.glsl"


/* ------ caustics ------ */

#include "/lib/util/bicubic.glsl"

const float viewDist = 0.0;

#include "/lib/atmos/waterConst.glsl"

vec3 shadowScreenToView(vec3 position, float warp) {
    position    = position * 2.0 - 1.0;
    position.z /= 0.2;
    position.xy *= warp;
    position    = projMAD(inverse(shadowProjection), position);

    return position;
}
vec3 shadowViewToScene(vec3 position) {
    position     = transMAD(inverse(shadowModelView), position);

    return position;
}

void main() {
    vec4 albedo     = texture(shadowcolor0, uv);
    vec3 auxData    = texture(shadowcolor1, uv).xyz;
    vec2 aux2       = unpack2x8(auxData.z);
    
    int matID       = decodeMatID8(aux2.y);

    vec2 depth      = vec2(texture(shadowtex0, uv).x, texture(shadowtex1, uv).x);

    float warp      = calculateWarp(uv * 2.0 - 1.0);

    vec3 viewPos0   = shadowScreenToView(vec3(uv, depth.x), warp);
    vec3 scenePos0  = shadowViewToScene(viewPos0);
    vec3 viewPos1   = shadowScreenToView(vec3(uv, depth.y), warp);
    vec3 scenePos1  = shadowViewToScene(viewPos1);

    data0           = vec4(vec3(0.25), 0.0);
    if (depth.x < depth.y) data0 = albedo * vec4(vec3(0.25), 1.0);
    
    if (matID == 102 || matID == 103) {     //Water
        float caustic   = albedo.r * 4.0;

        float surfaceDist = distance(scenePos0, scenePos1);
        surfaceDist = min(surfaceDist, 8.0);

        vec3 absorb     = exp(-max0(surfaceDist * waterDensity) * waterAbsorbCoeff);
            absorb     *= mix(caustic, 1.0, exp(-max0(surfaceDist) * sqrt2));

        data0           = vec4(absorb * 0.25, 1.0);
    }
}