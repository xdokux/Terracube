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

vec2 waveNoiseCubic(sampler2D tex, vec2 pos) {
    //vec2 size       = textureSize(tex, 0);
    //vec2 coord      = (pos.xy - (0.5 * (1.0 / 256.0)));
        pos        *= 256.0;
    ivec2 location  = ivec2(floor(pos));

    vec2 samples[4]    = vec2[4](
        texelFetch(tex, location                 & 255, 0).xy, texelFetch(tex, (location + ivec2(1, 0)) & 255, 0).xy,
        texelFetch(tex, (location + ivec2(0, 1)) & 255, 0).xy, texelFetch(tex, (location + ivec2(1, 1)) & 255, 0).xy
    );

    vec2 weights    = cubeSmooth(fract(pos));


    return mix(
        mix(samples[0], samples[1], weights.x),
        mix(samples[2], samples[3], weights.x), weights.y
    );
}

#define waterNormalOctaves 4
#define waterWaveStrength 1.0   //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

float waterWaves(vec3 pos, int matID) {
    #ifdef freezeAtmosAnim
        float time = float(atmosAnimOffset) * 0.76;
    #else
        float time  = frameTimeCounter * 0.76;
    #endif


    if (matID == 103) {
        time = 0.0;
        pos *= 0.66;
    }

    vec2 p      = pos.xz+pos.y*rcp(pi);

    vec2 dir    = normalize(vec2(0.4, 0.8));

    vec2 noise = (waveNoiseCubic(noisetex, (p + dir * time * 0.2) * 0.0008).rg * 2.0 - 1.0);
        p     += noise * 1.45;

    float wave  = 0.0;

    float amp   = 0.035;

    const float a = 1.1;
    const mat2 rotation = mat2(cos(a), -sin(a), sin(a), cos(a));

    vec2 noiseCoord = p * 0.0065;
    float distFalloff   = 1.0 - exp(-viewDist * rcp(32.0));

    float mult  = 1.0 - distFalloff * 0.9;

    for (uint i = 0; i<waterNormalOctaves; ++i) {
        float noise = waveNoiseCubic(noisetex, noiseCoord + dir * time * 0.01).r;

        wave   -= cubeSmooth(noise) * amp;

        time   *= 1.55;
        amp    *= 0.75;

        dir    *= rotation;
        noiseCoord *= 1.5;
    }

    return (wave - amp) * mult * waterWaveStrength;
}