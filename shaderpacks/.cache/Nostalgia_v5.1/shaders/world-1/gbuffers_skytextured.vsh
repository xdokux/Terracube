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

flat out vec3 sunColor;
flat out vec3 moonColor;

flat out vec3 sunDir;
flat out vec3 moonDir;

out vec3 viewDir;

out vec4 tint;

uniform int worldTime;

uniform vec2 taaOffset;

uniform mat4 gbufferModelView, gbufferModelViewInverse;

uniform vec4 daytime;

vec3 daytimeColor(vec3 rise, vec3 noon, vec3 set, vec3 night) {
    return rise * daytime.x + noon * daytime.y + set * daytime.z + night * daytime.w;
}

void main() {
    uv          = (gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;

    tint        = gl_Color;

    gl_Position = gl_ModelViewMatrix * gl_Vertex;

    viewDir     = normalize(gl_Position.xyz);

    gl_Position = gl_ProjectionMatrix * gl_Position;

    sunColor    = daytimeColor(
        vec3(0.79, 0.306, 0.03) * 0.70,
        vec3(1.00, 0.93, 0.72) * 1.00,
        vec3(0.79, 0.29, 0.04) * 0.70,
        vec3(0.69, 0.27, 0.04) * 0.10
        ) * 16.0 * pi;

    moonColor   = vec3(0.22, 0.33, 1.0) * 0.17 * 4.0;

    // Sun Position Fix from Builderb0y
    float ang   = fract(worldTime / 24000.0 - 0.25);
        ang     = (ang + (cos(ang * pi) * -0.5 + 0.5 - ang) / 3.0) * tau;
    const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));

    sunDir      = mat3(gbufferModelView) * vec3(-sin(ang), cos(ang) * sunRotationData);
    moonDir     = -sunDir;
}