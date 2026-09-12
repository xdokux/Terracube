#ifndef SHADOWS_GLSL
#define SHADOWS_GLSL

#include "settings.glsl"

uniform sampler2D shadowtex1;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform mat4 gbufferModelViewInverse;

// Deliberately hard-edged, single-sample shadow - no PCF. Soft
// shadow edges read as photorealistic; a crisp hard edge matches the
// flat, graphic look this pack is going for, and it's the cheapest
// possible shadow lookup as a side benefit.
float sampleShadow(vec3 viewPos) {
    vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
    vec4 shadowClip = shadowProjection * (shadowModelView * worldPos);
    vec3 shadowScreen = shadowClip.xyz / shadowClip.w * 0.5 + 0.5;

    if (shadowScreen.x < 0.0 || shadowScreen.x > 1.0 ||
        shadowScreen.y < 0.0 || shadowScreen.y > 1.0 ||
        shadowScreen.z < 0.0 || shadowScreen.z > 1.0) {
        return 1.0;
    }

    float currentDepth = shadowScreen.z - 0.0015;
    float shadowDepth = texture2D(shadowtex1, shadowScreen.xy).r;
    return step(currentDepth, shadowDepth);
}

#endif // SHADOWS_GLSL
