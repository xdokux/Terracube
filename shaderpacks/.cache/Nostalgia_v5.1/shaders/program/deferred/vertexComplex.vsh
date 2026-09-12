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
uniform vec2 viewSize;
#define VERTEX_STAGE
#include "/lib/downscaleTransform.glsl"


out vec2 uv;

vec3 blackbody(float temperature){
    vec4 vx = vec4(-0.2661239e9, -0.2343580e6, 0.8776956e3, 0.179910);
    vec4 vy = vec4(-1.1063814, -1.34811020, 2.18555832, -0.20219683);
    float it = rcp(temperature);
    float it2= sqr(it);
    float x = dot(vx, vec4(it * it2, it2, it, 1.0));
    float x2 = sqr(x);
    float y = dot(vy,vec4(x * x2, x2, x, 1.0));
    float z = 1.0 - x - y;
    
    vec3 AP1 = vec3(x * rcp(y), 1.0, z * rcp(y)) * CT_XYZ_AP1;
    return max(AP1, 0.0);
}

#ifndef DIM
#include "/lib/atmos/colorsDefault.glsl"
#elif DIM == -1
#include "/lib/atmos/colorsNether.glsl"
#elif DIM == 1
#include "/lib/atmos/colorsEnd.glsl"
#endif

#ifdef CLOUDPASS
flat out vec3 cloudSunlight;
flat out vec3 cloudSkylight;
#endif

void main() {
    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
    uv = gl_MultiTexCoord0.xy;

    getColorPalette();

    #ifdef CLOUDPASS
        cloudSunlight = daytimeColorSquared(
            vec3(0.67, 0.20, 0.05) * 0.45,
            vec3(0.95, 0.90, 0.76) * 0.90,
            vec3(0.65, 0.18, 0.04) * 0.45,
            vec3(0.65, 0.14, 0.03) * 0.25
            ) * 16.0 * 0.9;

        cloudSunlight   = colorSaturation(cloudSunlight, 1.0 - wetness * 0.65) * (1.0 - wetness * 0.5);

        vec3 linearSky  = srgbToPipelineColor(skyColor) * sqrt2;

        cloudSkylight = daytimeColor(
            linearSky * 1.00,
            linearSky * vec3(0.97, 1.18, 1.04) * 1.15,
            linearSky * 1.00,
            vec3(0.08, 0.50, 1.00) * 0.006
        ) * vec3(skyRedMult, skyGreenMult, skyBlueMult);

        cloudSkylight  = colorSaturation(cloudSkylight, 1.0 - wetness * 0.9) * (1.0 + wetness * 1.75);
        cloudSkylight *= mix(vec3(1.0), vec3(1.0, 1.2, 1.4), wetness);
    #endif

    #ifndef FULLRES_PASS
    VertexDownscaling(gl_Position, uv);
    #endif
}