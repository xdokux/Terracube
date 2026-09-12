#ifndef SHADOWS_GLSL
#define SHADOWS_GLSL

#include "settings.glsl"

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform mat4 gbufferModelViewInverse;

// Distortion warps shadow-map UV space so texels are denser near the
// player and sparser far away - this is what gives a single shadow
// map "cascade-like" behavior (higher effective resolution close up)
// without actually needing multiple shadow maps. MUST be applied
// identically in shadow.vsh (when rendering the map) and here (when
// sampling it), or the two won't line up.
vec2 distortShadowUV(vec2 uv) {
    vec2 centered = uv * 2.0 - 1.0;
    float distortFactor = length(centered) * SHADOW_DISTORTION + (1.0 - SHADOW_DISTORTION);
    return (centered / distortFactor) * 0.5 + 0.5;
}

vec3 toShadowScreenSpace(vec3 viewPos) {
    vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
    vec4 shadowClip = shadowProjection * (shadowModelView * worldPos);
    vec3 shadowNdc = shadowClip.xyz / shadowClip.w;
    vec3 shadowScreen = shadowNdc * 0.5 + 0.5;
    shadowScreen.xy = distortShadowUV(shadowScreen.xy);
    return shadowScreen;
}

float sampleShadow(vec3 viewPos) {
    vec3 shadowScreen = toShadowScreenSpace(viewPos);

    if (shadowScreen.x < 0.0 || shadowScreen.x > 1.0 ||
        shadowScreen.y < 0.0 || shadowScreen.y > 1.0 ||
        shadowScreen.z < 0.0 || shadowScreen.z > 1.0) {
        return 1.0;
    }

    float currentDepth = shadowScreen.z - 0.0012;
    float texelSize = 1.0 / float(SHADOW_RES);
    float sum = 0.0;
    int taps = 0;
    int radius = PCF_TAPS >= 4 ? 2 : 1;

    for (int x = -radius; x <= radius; x++) {
        for (int y = -radius; y <= radius; y++) {
            #if PCF_TAPS <= 2
                if (!((x == 0 || x == 1) && (y == 0 || y == 1))) continue;
            #endif
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            float shadowDepth = texture2D(shadowtex1, shadowScreen.xy + offset).r;
            sum += step(currentDepth, shadowDepth);
            taps++;
        }
    }

    return sum / float(taps);
}

#endif // SHADOWS_GLSL
