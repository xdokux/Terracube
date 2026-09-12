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
layout(location = 0) out vec3 skyCapture;

#include "/lib/head.glsl"

const vec2 viewSize     = vec2(512, 512);
const vec2 pixelSize    = 1.0 / viewSize;

in vec2 uv;

flat in vec3 skyColor;

//uniform vec3 sunDir, moonDir;

uniform vec3 lightDir;

uniform vec4 daytime;

uniform mat4 gbufferProjectionInverse, gbufferModelViewInverse;

#include "/lib/atmos/project.glsl"

float mieHG(float cosTheta, float g) {
    float mie   = 1.0 + sqr(g) - 2.0*g*cosTheta;
        mie     = (1.0 - sqr(g)) / ((4.0*pi) * mie*(mie*0.5+0.5));
    return mie;
}

vec3 skyGradient(vec3 direction) {
    return skyColor;
    /*
    float vDotS     = dot(direction, sunDir);
    float vDotM     = dot(direction, moonDir);

    float horizon   = exp(-max0(direction.y) * sqrPi);
        horizon    *= exp(-max0(-direction.y) * pi);

    float sunAmb    = saturate(1.35 * mieHG(vDotS, 0.2) / 0.2);

        horizon     = mix(horizon, horizon * sunAmb, sqr(daytime.x + daytime.z) * 0.8);

    float zenith    = exp(-max0(direction.y)) * 0.8 + 0.2;

    vec3 sunColor   = lightColor[0] * 0.2;

    float sunScatter = mieHG(vDotS, 0.78) * rpi * (1 - daytime.w);

    float glowAmount = cube(1 - linStep(direction.y, 0.0, 0.31)) * 0.96 * sunAmb;

    vec3 glowColor  = mix(skyColors[1], sunColor * skyColors[1] * 0.9 + sunColor * sunScatter, sstep(sunDir.y, -0.1, 0.01));
        glowColor   = mix(glowColor * 0.5, skyColors[0] * 0.5, 1.0 - exp(-max0(-direction.y - 0.06) * 0.71) * 0.8);

    vec3 sky        = skyColors[0] * zenith;
        sky         = mix(sky, glowColor, glowAmount);
        sky         = mix(sky, skyColors[1] * 1.2, horizon);
        sky        += sunColor * sunScatter * 1.35 * sqrt3;
        sky        += lightColor[1] * mieHG(vDotM, 0.74) * rpi * sqrt(daytime.w);

    return sky;
    */
}

void main() {
    vec2 projectionUV   = fract(uv * vec2(1.0, 2.0));

    if (uv.y < 0.5) {
        // Clear Sky Capture
        vec3 direction  = unprojectSky(projectionUV);

        skyCapture      = skyGradient(direction);
    } else {
        // Sky Capture with Clouds (for Reflections)
        vec3 direction  = unprojectSky(projectionUV);

        skyCapture      = skyGradient(direction);
        skyCapture     *= mix(exp(-max0(-direction.y) * cube(euler)), 1.0, 0.2);
    }
}