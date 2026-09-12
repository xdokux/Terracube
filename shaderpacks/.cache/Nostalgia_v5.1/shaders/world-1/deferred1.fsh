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


/* RENDERTARGETS: 0,5,7 */
layout(location = 0) out vec4 sceneColor;
layout(location = 1) out vec4 ssptData;
layout(location = 2) out vec3 directSunlight;

#include "/lib/head.glsl"
#include "/lib/util/encoders.glsl"
#include "/lib/util/colorspace.glsl"
#include "/lib/shadowconst.glsl"

const bool shadowHardwareFiltering = true;

in vec2 uv;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex5;
uniform sampler2D colortex15;

uniform sampler2D depthtex0;

uniform sampler2D noisetex;

uniform int frameCounter;

uniform float near, far;

uniform vec2 taaOffset;
uniform vec2 pixelSize, viewSize;

uniform vec3 lightDir, lightDirView;

uniform mat4 gbufferModelView, gbufferModelViewInverse;
uniform mat4 gbufferProjection, gbufferProjectionInverse;
/* ------ includes ------*/
#define FUTIL_MAT16
#define FUTIL_LINDEPTH
#include "/lib/fUtil.glsl"
#include "/lib/util/transforms.glsl"
#include "/lib/frag/bluenoise.glsl"
#include "/lib/frag/gradnoise.glsl"

#include "/lib/offset/random.glsl"

/* ------ BRDF ------ */

#include "/lib/brdf/fresnel.glsl"
#include "/lib/brdf/hammon.glsl"
#include "/lib/brdf/labPBR.glsl"

vec3 fauxPorosity(vec3 albedo, float wetness, float porosity) {
    //wetness = 1.0;
    vec3 wetAlbedo      = colorSaturation(mix(albedo * sqrt(albedo), sqr(albedo), getLuma(albedo)), 0.85);
        //wetAlbedo       = albedo;
    float frcBounced    = 0.7 * porosity;
        wetAlbedo      = (1.0 - frcBounced) * wetAlbedo / (1.0 - frcBounced * wetAlbedo);

    return mix(albedo, wetAlbedo, wetness);
}


#include "/lib/light/emission.glsl"


void main() {
    sceneColor      = stex(colortex0);
    directSunlight  = vec3(0.0);

    float sceneDepth = stex(depthtex0).x;

    vec3 emissionColor  = vec3(0);

    vec4 gbufferData    = vec4(0.0, 0.0, 1.0, 1.0);

    ssptData            = vec4(0, 0, 1, 0);

    if (landMask(sceneDepth)) {
        vec4 tex1       = stex(colortex1);
        vec4 tex2       = stex(colortex2);

        vec3 viewPos    = screenToViewSpace(vec3(uv, sceneDepth));
        vec3 viewDir    = -normalize(viewPos);
        vec3 scenePos   = viewToSceneSpace(viewPos);

        vec3 sceneNormal = decodeNormal(tex1.xy);
        vec3 viewNormal = mat3(gbufferModelView) * sceneNormal;

        ssptData.rgb    = sceneNormal * 0.5 + 0.5;

        materialLAB material = decodeSpecularTexture(vec4(unpack2x8(tex2.x), unpack2x8(tex1.a)));

        ivec2 matID     = unpack2x8I(tex2.y);

        material.emission = pow(material.emission, labEmissionCurve);

        float albedoLum = mix(avgOf(sceneColor.rgb), maxOf(sceneColor.rgb), 0.71);
            albedoLum   = saturate(albedoLum * sqrt2);

        float emitterLum = saturate(mix(sqr(albedoLum), sqrt(maxOf(sceneColor.rgb)), albedoLum));

        #if ssptEmissionMode >= 1
            ssptData.a     = getEmitterBrightness(matID.y, material.emission, emitterLum);
        #else
            ssptData.a     = getEmitterBrightness(matID.y) * emitterLum;
        #endif

        sceneColor.a    = ssptData.a;
    }

    ssptData    = clamp16F(ssptData);
    sceneColor  = clamp16F(sceneColor);
}