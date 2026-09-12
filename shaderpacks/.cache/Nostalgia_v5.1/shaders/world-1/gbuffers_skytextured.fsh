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

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 sceneAlbedo;

#include "/lib/head.glsl"
#include "/lib/util/colorspace.glsl"

in vec2 uv;

in vec3 viewDir;

in vec4 tint;

flat in vec3 sunColor;
flat in vec3 moonColor;
flat in vec3 sunDir;
flat in vec3 moonDir;

uniform sampler2D gcolor;

uniform vec4 daytime;

uniform mat4 gbufferModelViewInverse;

vec3 daytimeColor(vec3 rise, vec3 noon, vec3 set, vec3 night) {
    return rise * daytime.x + noon * daytime.y + set * daytime.z + night * daytime.w;
}

void main() {
    vec4 sceneColor   = texture(gcolor, uv);
        sceneColor.rgb *= tint.rgb;
        convertToPipelineAlbedo(sceneColor.rgb);

    float isSun     = sstep(dot(viewDir, sunDir), 0.0, 0.9);
    float isMoon    = sstep(dot(viewDir, moonDir), 0.0, 0.9);
        
        sceneColor.rgb *= isSun * sunColor + isMoon * moonColor;

    vec3 worldDir   = mat3(gbufferModelViewInverse) * viewDir;

    sceneColor.a  *= exp(-max0(-worldDir.y) * 64.0);

    sceneAlbedo     = clamp16F(sceneColor);
}