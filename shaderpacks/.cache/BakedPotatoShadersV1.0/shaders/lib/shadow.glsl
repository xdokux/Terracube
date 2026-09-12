#ifndef CINDERLIGHT_SHADOW_GLSL
#define CINDERLIGHT_SHADOW_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"

uniform sampler2D shadowtex0;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

const float CINDERLIGHT_SHADOW_DISTORTION = 0.86;

float getShadowDistortion(vec2 shadowClipXY) {
    return (1.0 - CINDERLIGHT_SHADOW_DISTORTION) + length(shadowClipXY) * CINDERLIGHT_SHADOW_DISTORTION;
}

vec3 getShadowCoord(vec3 playerPosition) {
    vec4 shadowPosition = shadowProjection * shadowModelView * vec4(playerPosition, 1.0);
    shadowPosition.xy /= getShadowDistortion(shadowPosition.xy);
    shadowPosition.z *= 0.5;
    shadowPosition.xyz /= shadowPosition.w;
    return shadowPosition.xyz * 0.5 + 0.5;
}

float compareShadowDepth(vec2 uv, float receiverDepth) {
    return step(receiverDepth, texture2D(shadowtex0, uv).r);
}

float sampleSoftShadow(vec3 playerPosition, float normalDotLight, float skyLight) {
#if SHADOW_QUALITY == 0
    return 1.0;
#else
    float radialDistance = length(playerPosition.xz);
    float distanceFade = 1.0 - smoothstep(shadowDistance * 0.78, shadowDistance, radialDistance);
    if (distanceFade <= 0.001 || skyLight <= 0.015) return 1.0;

    vec3 shadowCoord = getShadowCoord(playerPosition);
    if (shadowCoord.x <= 0.001 || shadowCoord.x >= 0.999 ||
        shadowCoord.y <= 0.001 || shadowCoord.y >= 0.999 ||
        shadowCoord.z <= 0.0 || shadowCoord.z >= 1.0) return 1.0;

    float slope = 1.0 - saturate(normalDotLight);
    float receiverDepth = shadowCoord.z - mix(0.00016, 0.00068, slope);
    float texel = 1.0 / float(shadowMapResolution);
    float visibility = 0.0;

#if SHADOW_QUALITY == 1
    visibility += compareShadowDepth(shadowCoord.xy, receiverDepth) * 0.28;
    visibility += compareShadowDepth(shadowCoord.xy + vec2( texel, 0.0), receiverDepth) * 0.18;
    visibility += compareShadowDepth(shadowCoord.xy + vec2(-texel, 0.0), receiverDepth) * 0.18;
    visibility += compareShadowDepth(shadowCoord.xy + vec2(0.0,  texel), receiverDepth) * 0.18;
    visibility += compareShadowDepth(shadowCoord.xy + vec2(0.0, -texel), receiverDepth) * 0.18;
#else
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            visibility += compareShadowDepth(shadowCoord.xy + vec2(float(x), float(y)) * texel, receiverDepth) / 9.0;
        }
    }
#endif

    float influence = distanceFade * smoothstep(0.02, 0.32, skyLight);
    return mix(1.0, visibility, influence);
#endif
}

#endif
