
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

/* RENDERTARGETS: 5 */
layout(location = 0) out vec4 indirectCurrent;

#include "/lib/head.glsl"
#include "/lib/util/encoders.glsl"

in vec2 uv;

uniform sampler2D colortex3;
uniform sampler2D colortex5;
uniform sampler2D colortex13;

uniform sampler2D depthtex0;

uniform sampler2D noisetex;

uniform int frameCounter;

uniform float far, near;
uniform float screenBrightness;

uniform vec2 viewSize;

#include "/lib/frag/bluenoise.glsl"

#define maxFrames 256

#define colorSampler colortex5
#define gbufferSampler colortex3

#define colorHistorySampler colortex13
#define gbufferHistorySampler colortex12

#define SVGF_RAD 1              //[1 2 3] Filter Radius
#define SVGF_STRICTNESS 1.0     //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0] Luminance Strictness
#define SVGF_NORMALEXP 1.0      //[0.2 0.4 0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0]

/* ------ ATROUS ------ */

#include "/lib/offset/gauss.glsl"

ivec2 clampTexelPos(ivec2 pos) {
    return clamp(pos, ivec2(0.0), ivec2(viewSize));
}

vec2 computeVariance(sampler2D tex, ivec2 pos) {
    float sumMsqr   = 0.0;
    float sumMean   = 0.0;

    for (int i = 0; i<9; i++) {
        ivec2 deltaPos     = kernelO_3x3[i];

        vec3 col    = texelFetch(tex, clampTexelPos(pos + deltaPos), 0).rgb;
        float lum   = getLuma(col);

        sumMsqr    += sqr(lum);
        sumMean    += lum;
    }
    sumMsqr  /= 9.0;
    sumMean  /= 9.0;

    return vec2(abs(sumMsqr - sqr(sumMean)) * rcp(max(sumMean, 1e-20)), sumMean);
}

vec4 FetchGbuffer(ivec2 UV) {
    vec4 Val  = texelFetch(gbufferSampler, UV, 0);
    return vec4(Val.rgb * 2.0 - 1.0, sqr(Val.w) * far);
}

vec3 atrousSVGF(sampler2D tex, vec2 uv, const int size) {
    ivec2 UV           = ivec2(uv * viewSize);

    vec4 centerData     = FetchGbuffer(UV);

    vec3 centerColor    = texelFetch(tex, UV, 0).rgb;
    float centerLuma    = getLuma(centerColor.rgb);

    //return centerColor;

    vec2 variance       = computeVariance(tex, UV);

    float pixelAge      = texelFetch(colorHistorySampler, UV, 0).a;

    vec3 total          = centerColor;
    float totalWeight   = 1.0;

    //float sizeMult      = size > 2 ? (fract(ditherBluenoise() + float(size) / euler) + 0.5) * float(size) : float(size);
    //    sizeMult        = mix(float(size), sizeMult, cube(pixelAge));

    //ivec2 jitter        = ivec2(temporalBluenoise() - 0.5) * size;

    float frames    = pixelAge;

    float sigmaBias = (1.0 / max(frames / 2, 1.0)) + 0.28;
    float offset    = mix(0.18 / (0.5 * SVGF_RAD), 0.031, saturate(frames / 32.0));
    float maxDelta  = mix(halfPi, tau, saturate(frames / 32.0));
    float sigmaMul  = mix(1.41, 0.21, saturate(frames / 32.0));

    float sigmaDistMul = 2.0 - (1.0 / (1.0 + centerData.a / 64.0));

	float sigmaL = 1.0 / (sigmaMul * SVGF_STRICTNESS * sigmaDistMul * variance.x + sigmaBias * sigmaDistMul);

    float normalExp = mix(2.0, 8.0, saturate(frames / 8.0)) * SVGF_NORMALEXP;

	const int r = SVGF_RAD;
	for(int y = -r; y <= r; ++y) {
		for(int x = -r; x <= r; ++x) {
			ivec2 p = UV + ivec2(x, y) * size;

			if(x == 0 && y == 0)
				continue;

            bool valid          = all(greaterThanEqual(p, ivec2(0))) && all(lessThan(p, ivec2(viewSize)));

            if (!valid) continue;

            vec4 currentData    = FetchGbuffer(p);

            vec3 currentColor   = texelFetch(tex, clampTexelPos(p), 0).rgb;
            float currentLuma   = getLuma(currentColor.rgb);

            float w         = float(valid);

            float distLum   = abs(centerLuma - currentLuma);
                distLum     = sqr(distLum) / max(centerLuma, offset);
                distLum     = clamp(distLum, 0.0, maxDelta);

            float distDepth = abs(centerData.a - currentData.a) * 4.0;

                w *= pow(max(0.0, dot(centerData.rgb, currentData.rgb)), normalExp);
                w *= exp(-distDepth / sqrt(float(size)) - sqrt(distLum * sigmaL));

            //accumulate stuff
            total       += currentColor * w;

            totalWeight += w;
        }
    }

    //compensate for total sampling weight
    total *= rcp(max(totalWeight, 1e-25));

    return total;
}


void main() {
    vec2 lowresCoord    = uv / indirectResScale;
    ivec2 pixelPos      = ivec2(floor(uv * viewSize) / indirectResScale);
    indirectCurrent     = vec4(0.0);
    indirectCurrent.a = stex(colorSampler).a;

    if (saturate(lowresCoord) == lowresCoord) {
        #ifdef SVGF_FILTER
            if (landMask(texelFetch(depthtex0, pixelPos, 0).x)) indirectCurrent.rgb = clamp16F(atrousSVGF(colorSampler, uv, SVGF_SIZE));
            else indirectCurrent = clamp16F(stex(colorSampler));
        #else
            indirectCurrent = clamp16F(stex(colorSampler));
        #endif
    }
}