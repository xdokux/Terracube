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


#include "/lib/head.glsl"

/* RENDERTARGETS: 5 */
layout(location = 0) out float vpsSigmaStore;

#include "/lib/util/colorspace.glsl"

const bool shadowHardwareFiltering = false;

in vec2 uv;

uniform sampler2D depthtex0;

uniform sampler2D noisetex;

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;

uniform int frameCounter;
uniform int worldTime;

uniform float far, near;
uniform float rainStrength;

uniform vec2 skyCaptureResolution;
uniform vec2 taaOffset;
uniform vec2 pixelSize, viewSize;

uniform vec3 lightDir;

uniform vec4 daytime;

uniform mat4 gbufferModelView, gbufferModelViewInverse;
uniform mat4 gbufferProjection, gbufferProjectionInverse;
uniform mat4 shadowModelView, shadowProjection;

/* ------ includes ------*/
#define FUTIL_LINDEPTH
#define FUTIL_ROT2
#include "/lib/fUtil.glsl"
#include "/lib/util/encoders.glsl"

#include "/lib/util/transforms.glsl"
#include "/lib/util/bicubic.glsl"
#include "/lib/frag/gradnoise.glsl"

/* ------ SHADOWPASS PRECOMPUTION ------ */

#include "/lib/shadowconst.glsl"
#include "/lib/light/warp.glsl"

#include "/lib/offset/random.glsl"


float shadowVPSSigma(sampler2D tex, vec3 scenePos) {    
    vec3 pos        = scenePos + vec3(shadowmapBias) * lightDir;
    float a         = length(pos);
        pos         = transMAD(shadowModelView, pos);
        pos         = projMAD(shadowProjection, pos);

        pos.z      *= 0.2;

    if (pos.z > 1.0) return 0.0;

        pos.z      -= 0.0012*(saturate(a/256.0));

    vec2 posUnwarped = pos.xy;

    float warp      = 1.0;
        pos.xy      = shadowmapWarp(pos.xy, warp);
        pos         = pos * 0.5 + 0.5;

    const uint iterations = 6;

    const float penumbraScale = tan(radians(0.5 * shadowPenumbraScale));

    float penumbraMax   = shadowmapDepthScale * penumbraScale * shadowProjection[0].x;
    float searchRad     = min(0.5 * shadowProjection[0].x, penumbraMax / tau);

    float maxRad        = max(searchRad, 2.0 / shadowmapSize.x / warp);

    float minDepth      = pos.z - maxRad / penumbraMax / tau;
    float maxDepth      = pos.z;

    const uint itSquare = iterations * iterations;
    const float w = 1.0 / float(itSquare);

    float weightSum = 0.0;
    float depthSum  = 0.0;

    float dither    = ditherGradNoiseTemporal();

    for (uint i = 0; i<iterations; ++i) {
        vec2 offset     = R2((i + dither) * 64.0);
            offset      = vec2(cos(offset.x * tau), sin(offset.x * tau)) * sqrt(offset.y);            

        vec2 searchPos  = posUnwarped + offset * searchRad;
            searchPos   = shadowmapWarp(searchPos) * 0.5 + 0.5;

        float depth     = texelFetch(tex, ivec2(searchPos * shadowmapSize), 0).x;
        float weight    = step(depth, pos.z);

            depthSum   += weight * clamp(depth, minDepth, maxDepth);
            weightSum  += weight;
    }
    depthSum   /= weightSum > 0.0 ? weightSum : 1.0;

    float sigma     = weightSum > 0.0 ? (pos.z - depthSum) * penumbraMax : 0.0;

    return max0(sigma) * rcp(warp);
}

void main() {
    float sceneDepth = texture(depthtex0, uv).x;

    vec3 viewPos    = screenToViewSpace(vec3(uv / ResolutionScale, sceneDepth));
    vec3 scenePos   = viewToSceneSpace(viewPos);

    vpsSigmaStore   = 0.0;

    if (landMask(sceneDepth)) vpsSigmaStore = shadowVPSSigma(shadowtex1, scenePos);

    vpsSigmaStore   = clamp16F(vpsSigmaStore);
}