#ifndef SHADOWS_GLSL
#define SHADOWS_GLSL

#include "settings.glsl"

// Declared as sampler2DShadow (not a plain sampler2D) to get
// hardware-accelerated shadow comparison: the GPU bilinearly filters
// the DEPTH COMPARE RESULT itself across the 4 nearest texels, in one
// texture fetch, for free. That's what actually gives a crisp-but-
// not-jittery edge here - a manually-filtered depth value compared
// afterward would only smooth the depth threshold, not the edge
// itself; hardware shadow sampling smooths the edge directly.
uniform sampler2DShadow shadowtex1;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform mat4 gbufferModelViewInverse;

// One texel's approximate world-space size, used to scale the normal
// offset below. SHADOW_DISTANCE is the orthographic frustum's rough
// half-extent, so 2x that spread over SHADOW_RES texels gives a
// reasonable per-texel size estimate.
float shadowTexelWorldSize() {
    return (SHADOW_DISTANCE * 2.0) / float(SHADOW_RES);
}

vec3 toShadowScreenSpace(vec3 worldPos) {
    vec4 shadowClip = shadowProjection * (shadowModelView * vec4(worldPos, 1.0));
    return shadowClip.xyz / shadowClip.w * 0.5 + 0.5;
}

// Normal-offset bias: push the sample point along the surface normal,
// in WORLD space, before projecting into shadow space - not a depth
// bias tweak. This is what actually kills both shadow acne and the
// swimming/shimmering that shows up as the camera moves, without
// needing PCF blur (which would soften edges you explicitly want
// crisp) or a large depth bias (which causes visible peter-panning,
// shadows detaching from the objects casting them).
float sampleShadow(vec3 viewPos, vec3 viewNormal) {
    vec4 worldPos4 = gbufferModelViewInverse * vec4(viewPos, 1.0);
    vec3 worldNormal = mat3(gbufferModelViewInverse) * viewNormal;

    float offset = shadowTexelWorldSize() * NORMAL_OFFSET_TEXELS;
    vec3 worldPos = worldPos4.xyz + worldNormal * offset;

    vec3 shadowScreen = toShadowScreenSpace(worldPos);

    if (shadowScreen.x < 0.0 || shadowScreen.x > 1.0 ||
        shadowScreen.y < 0.0 || shadowScreen.y > 1.0 ||
        shadowScreen.z < 0.0 || shadowScreen.z > 1.0) {
        return 1.0;
    }

    // Single hardware-filtered compare, one fetch. The GPU compares
    // the biased reference depth against the 4 nearest shadow-map
    // texels and blends the pass/fail results - not the depth values
    // - giving a smoothly-positioned edge instead of a texel-snapped
    // staircase, without turning into a soft PCF blur.
    float bias = 0.0006;
    return texture(shadowtex1, vec3(shadowScreen.xy, shadowScreen.z - bias));
}

#endif // SHADOWS_GLSL
