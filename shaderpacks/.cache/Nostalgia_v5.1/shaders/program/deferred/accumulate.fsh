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

/* RENDERTARGETS: 5,12,13 */
layout(location = 0) out vec4 indirectCurrent;
layout(location = 1) out vec4 historyGData;
layout(location = 2) out vec4 indirectHistory;

#include "/lib/head.glsl"
#include "/lib/util/encoders.glsl"

const bool colortex12Clear   = false;
const bool colortex13Clear   = false;

in vec2 uv;

flat in vec3 blocklightColor;

uniform sampler2D colortex1;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex12;
uniform sampler2D colortex13;

uniform sampler2D depthtex0;
uniform sampler2D depthtex2;

#ifdef ssptEnabled

uniform float far, near;

uniform vec2 pixelSize, viewSize;
uniform vec2 taaOffset;

uniform vec3 cameraPosition, previousCameraPosition;

uniform mat4 gbufferModelView, gbufferModelViewInverse;
uniform mat4 gbufferProjection, gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection, gbufferPreviousModelView;

#define FUTIL_MAT16
#include "/lib/fUtil.glsl"
#include "/lib/util/transforms.glsl"

/* ------ reprojection ----- */
vec3 reproject(vec3 sceneSpace, bool hand) {
    vec3 prevScreenPos = hand ? vec3(0.0) : cameraPosition - previousCameraPosition;
    prevScreenPos = sceneSpace + prevScreenPos;
    prevScreenPos = transMAD(gbufferPreviousModelView, prevScreenPos);
    prevScreenPos = transMAD(gbufferPreviousProjection, prevScreenPos) * (0.5 / -prevScreenPos.z) + 0.5;

    return prevScreenPos;
}

#define maxFrames 256

#define colorSampler colortex5
#define gbufferSampler colortex3

#define colorHistorySampler colortex13
#define gbufferHistorySampler colortex12

/* ------ ATROUS ------ */

vec4 FetchGbuffer(ivec2 UV) {
    vec4 Val  = texelFetch(gbufferSampler, UV, 0);
    return vec4(Val.rgb * 2.0 - 1.0, sqr(Val.w));
}

vec3 spatialColor(vec2 uv) {
    ivec2 UV    = ivec2(uv * viewSize);

    vec3 totalColor     = texelFetch(colorSampler, UV, 0).rgb;
    float sumWeight     = 1.0;
    float lumaCenter    = getLuma(totalColor);

    vec4 GBuffer        = FetchGbuffer(UV);

	const int r = 2;
	for(int y = -r; y <= r; ++y) {
		for(int x = -r; x <= r; ++x) {
            if (x == 0 && y == 0) continue;

            ivec2 TapUV = UV + ivec2(x, y);

            vec4 GB     = FetchGbuffer(TapUV);

            float depthDelta = distance(GB.w, GBuffer.w) * far;

            if (depthDelta < 2.0) {
                vec3 currentColor = texelFetch(colorSampler, TapUV, 0).rgb;

                float lum       = getLuma(currentColor);

                float distLum   = abs(lumaCenter - lum);
                    distLum     = sqr(distLum) / max(lumaCenter, 0.027);
                    distLum     = clamp(distLum, 0.0, pi);

                float weight    = pow(max0(dot(GBuffer.xyz, GB.xyz)), 8.0) * exp(-depthDelta - sqrt(distLum) * rpi);
                    //weight     *= gaussKernel[abs(x)][abs(y)];

                totalColor     += currentColor * weight;
                sumWeight      += weight;
            }
        }
    }
    totalColor /= sumWeight;

    return totalColor;
}
vec3 spatialColor7x7(vec2 uv) {
    ivec2 UV    = ivec2(uv * viewSize);

    vec3 totalColor     = texelFetch(colorSampler, UV, 0).rgb;
    float sumWeight     = 1.0;
    float lumaCenter    = getLuma(totalColor);

    vec4 GBuffer        = FetchGbuffer(UV);

	const int r = 3;
	for(int y = -r; y <= r; ++y) {
		for(int x = -r; x <= r; ++x) {
            if (x == 0 && y == 0) continue;

            ivec2 TapUV = UV + ivec2(x, y);

            vec4 GB     = FetchGbuffer(TapUV);

            float depthDelta = distance(GB.w, GBuffer.w) * far;

            if (depthDelta < 2.0) {
                vec3 currentColor = texelFetch(colorSampler, TapUV, 0).rgb;

                float weight    = pow(max0(dot(GBuffer.xyz, GB.xyz)), 2.0);

                totalColor     += currentColor * weight;
                sumWeight      += weight;
            }
        }
    }
    totalColor /= sumWeight;

    return totalColor;
}

#endif

vec3 getBlocklightMap(vec3 color, float intensity) {
    color *= mix((normalize(color)), vec3(1.0), sqrt(intensity));
    return (intensity) * color;
}

void main() {
    historyGData    = vec4(1.0);
    indirectHistory = vec4(0.0);
    indirectCurrent = stex(colortex5);

    #ifdef ssptEnabled

    vec2 lowresCoord    = uv / indirectResScale;
    ivec2 pixelPos      = ivec2(floor(uv * viewSize) / indirectResScale);
    float sceneDepth    = texelFetch(depthtex0, pixelPos, 0).x;

    if (landMask(sceneDepth) && saturate(lowresCoord) == lowresCoord) {
        vec2 uv         = saturate(lowresCoord);
        vec2 scaledUv   = uv * indirectResScale;

        vec3 viewPos    = screenToViewSpace(vec3(uv / ResolutionScale, sceneDepth), false);
        vec3 scenePos   = viewToSceneSpace(viewPos);

        bool hand       = sceneDepth < texelFetch(depthtex2, pixelPos, 0).x;

        float currentDistance   = saturate(length(scenePos) / far);

        vec3 reprojection   = reproject(scenePos, false);
        bool offscreen      = saturate(reprojection.xy) != reprojection.xy;

        vec2 scaledReprojection = reprojection.xy * indirectResScale * ResolutionScale;

        vec4 historyGbuffer = texture(gbufferHistorySampler, scaledReprojection.xy);
            historyGbuffer.rgb = historyGbuffer.rgb * 2.0 - 1.0;
            historyGbuffer.a = sqr(historyGbuffer.a);

        vec3 cameraMovement = mat3(gbufferModelView) * (cameraPosition - previousCameraPosition);

        vec3 rtLight    = vec3(0.0);
        float samples   = 0.0;

        if (offscreen) {
            rtLight     = spatialColor7x7(scaledUv);
            samples     = 1.0;
        } else {
            vec4 previousLight  = vec4(0);

            // Sample History
            ivec2 repPixel  = ivec2(floor(scaledReprojection.xy * viewSize - vec2(0.5)));
            vec2 subpix     = fract(scaledReprojection.xy * viewSize - vec2(0.5) - repPixel);

            const ivec2 offset[4] = ivec2[4](
                ivec2(0, 0),
                ivec2(1, 0),
                ivec2(0, 1),
                ivec2(1, 1)
            );

            float weight[4]     = float[4](
                (1.0 - subpix.x) * (1.0 - subpix.y),
                subpix.x         * (1.0 - subpix.y),
                (1.0 - subpix.x) * subpix.y,
                subpix.x         * subpix.y
            );

            float sumWeight     = 0.0;

            for (uint i = 0; i < 4; ++i) {
                ivec2 UV            = repPixel + offset[i];

                float depthDelta    = distance(sqr(texelFetch(gbufferHistorySampler, UV, 0).a), currentDistance) - abs(cameraMovement.z / far);
                bool depthRejection = (depthDelta / abs(currentDistance)) < 0.1;

                if (depthRejection) {
                    previousLight  += clamp16F(texelFetch(colorHistorySampler, UV, 0)) * weight[i];
                    sumWeight      += weight[i];
                }
            }

            if (sumWeight > 1e-3) {
                vec3 rtCurrent  = spatialColor(scaledUv);
                previousLight      /= sumWeight;

                float frames        = min(previousLight.a + 1.0, maxFrames);
                float alphaColor    = max(0.01, 1.0 / frames);

                rtLight             = mix(previousLight.rgb, rtCurrent, alphaColor);
                samples             = frames;
            } else {
                rtLight     = spatialColor7x7(scaledUv);
                samples     = 1.0;
            }
        }

        float lightmap      = texture(colorSampler, scaledUv).a;

        indirectCurrent.rgb     = rtLight + lightmap * blocklightColor / tau;

        indirectHistory     = clamp16F(vec4(rtLight, samples));
        historyGData        = saturate(vec4(texture(gbufferSampler, scaledUv).xyz, sqrt(currentDistance)));

    }

    #endif

    indirectCurrent     = clamp16F(indirectCurrent);
    indirectHistory     = clamp16F(indirectHistory);
}