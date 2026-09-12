/*
    shadows.glsl
    ---------------------------------------------------------------
    Shadow map projection + PCF sampling, shared by every gbuffers_*
    fragment shader that receives shadows (terrain, water, entities).

    Deliberately NOT doing colored/translucent shadows (e.g. tinted
    shadows under stained glass) - that requires a second shadow
    color attachment and roughly doubles shadow-pass bandwidth cost,
    which isn't worth it for this pack's goals. Easy to add later
    as an opt-in "ultra" toggle if wanted.
    ---------------------------------------------------------------
*/
#ifndef SHADOWS_GLSL
#define SHADOWS_GLSL


uniform sampler2D shadowtex0; // shadow-pass depth, all shadow casters
uniform sampler2D shadowtex1; // shadow-pass depth, opaque casters only
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform mat4 gbufferModelViewInverse;

#include "settings.glsl"

// Projects a view-space position into shadow-map [0,1] screen space.
// Iris's default shadow distortion (fisheye-style, more resolution
// near the player) is applied automatically via the shadow map
// itself when SHADOW_DISTANCE/SHADOW_RES are set through
// shaders.properties, so no manual distortion math is needed here.
vec3 toShadowScreenSpace(vec3 viewPos) {
    vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
    vec4 shadowClip = shadowProjection * (shadowModelView * worldPos);
    vec3 shadowScreen = shadowClip.xyz / shadowClip.w;
    return shadowScreen * 0.5 + 0.5; // NDC [-1,1] -> [0,1]
}

// Returns 0 (fully shadowed) .. 1 (fully lit). PCF_TAPS controls how
// many samples are taken - this is the #1 lever for shadow cost on
// weak GPUs since each tap is a full texture fetch against the
// shadow depth map.
float sampleShadow(vec3 viewPos) {
    vec3 shadowScreen = toShadowScreenSpace(viewPos);

    // Outside the shadow frustum entirely (beyond SHADOW_DISTANCE) -
    // treat as fully lit rather than sampling garbage/clamped texels.
    if (shadowScreen.x < 0.0 || shadowScreen.x > 1.0 ||
        shadowScreen.y < 0.0 || shadowScreen.y > 1.0 ||
        shadowScreen.z < 0.0 || shadowScreen.z > 1.0) {
        return 1.0;
    }

    float currentDepth = shadowScreen.z - 0.0012; // slope-independent bias

#if PCF_TAPS <= 1
    // Single hard sample - cheapest possible path, used on igpu.
    float shadowDepth = texture(shadowtex1, shadowScreen.xy).r;
    return step(currentDepth, shadowDepth);
#else
    // Small fixed-pattern PCF kernel. Deliberately a plain small loop
    // rather than a separable two-pass blur: shadow PCF operates on a
    // single depth value per tap (not a wide color kernel), so a
    // one-pass NxN grid is already cheap and a second full-screen
    // pass would cost more than it saves at this tap count.
    float texelSize = 1.0 / float(SHADOW_RES);
    float sum = 0.0;
    int taps = 0;

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            #if PCF_TAPS <= 2
                if (!((x == 0 || x == 1) && (y == 0 || y == 1))) continue;
            #endif
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            float shadowDepth = texture(shadowtex1, shadowScreen.xy + offset).r;
            sum += step(currentDepth, shadowDepth);
            taps++;
        }
    }

    return sum / float(taps);
#endif
}

#endif // SHADOWS_GLSL
