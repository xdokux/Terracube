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

out vec2 uv;

out vec3 viewDir;

out vec4 tint;

uniform int worldTime;

uniform vec2 taaOffset;

uniform mat4 gbufferModelView, gbufferModelViewInverse;

void main() {
    uv          = (gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;

    tint        = gl_Color;

    gl_Position = gl_ModelViewMatrix * gl_Vertex;

    viewDir     = normalize(gl_Position.xyz);

    gl_Position = gl_ProjectionMatrix * gl_Position;
}