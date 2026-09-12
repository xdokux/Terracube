/*
    composite.fsh
    ---------------------------------------------------------------
    Pipeline stage: COMPOSITE (post-processing, full screen)
    Reads: colortex0 (lit scene from the gbuffers_* passes), depthtex0
           (scene depth), shadowtex1 (for god-ray visibility sampling)
    Writes: colortex0, with god rays added on top

    God rays here work by raymarching in VIEW SPACE from the camera
    out to each fragment's depth, sampling shadow-map visibility at
    each step, and accumulating light where the ray was unoccluded.
    This is the same core technique used by most lightweight OptiFine/
    Iris packs (Sildur's included) for shafts-through-gaps-in-geometry,
    as opposed to a full 3D volumetric fog integrator - much cheaper,
    and it's why GODRAY_STEPS is the only real cost dial here.
    ---------------------------------------------------------------
*/
#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex1;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform float far;
uniform float near;

varying vec2 texCoord;

// Reconstructs view-space position from depth-buffer depth + texcoord.
vec3 viewPosFromDepth(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

// Cheap dither pattern (interleaved gradient noise) to jitter the
// raymarch start point per-pixel - kills banding between visible
// steps without needing more steps. One sin() call, negligible cost.
float ditherPattern(vec2 screenPos) {
    return fract(52.9829189 * fract(dot(screenPos, vec2(0.06711056, 0.00583715))));
}

void main() {
    vec3 color = texture2D(colortex0, texCoord).rgb;

#if GODRAYS == 1
    float depth = texture2D(depthtex0, texCoord).r;
    vec3 fragViewPos = viewPosFromDepth(texCoord, depth);

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);

    // Skip the whole raymarch below the horizon or in heavy rain -
    // god rays from a moon are subtle enough not to be worth the
    // cost, and rain clouds block them anyway in vanilla's model.
    if (lightDir.y > 0.02 && rainStrength < 0.9) {
        vec3 lightColor = getSunMoonColor(dayFactor);

        // Marching distance is capped well short of full render
        // distance - god rays are a near-camera atmospheric effect;
        // marching to the horizon would waste steps on a region
        // where the effect is barely visible anyway.
        float marchDistance = min(length(fragViewPos), 48.0);
        vec3 rayDir = normalize(fragViewPos);

        float dither = ditherPattern(gl_FragCoord.xy);
        float stepSize = marchDistance / float(GODRAY_STEPS);

        float accumulated = 0.0;
        for (int i = 0; i < GODRAY_STEPS; i++) {
            float t = (float(i) + dither) * stepSize;
            vec3 samplePos = rayDir * t;

            vec4 worldPos = gbufferModelViewInverse * vec4(samplePos, 1.0);
            vec4 shadowClip = shadowProjection * (shadowModelView * worldPos);
            vec3 shadowScreen = shadowClip.xyz / shadowClip.w * 0.5 + 0.5;

            if (shadowScreen.x >= 0.0 && shadowScreen.x <= 1.0 &&
                shadowScreen.y >= 0.0 && shadowScreen.y <= 1.0 &&
                shadowScreen.z >= 0.0 && shadowScreen.z <= 1.0) {
                float shadowDepth = texture2D(shadowtex1, shadowScreen.xy).r;
                accumulated += step(shadowScreen.z - 0.0015, shadowDepth);
            } else {
                // Outside shadow frustum (far from player) - treat as
                // unoccluded so rays don't cut off in a visible ring
                // at the shadow-distance boundary.
                accumulated += 1.0;
            }
        }
        accumulated /= float(GODRAY_STEPS);

        // Fade rays out near the horizon/dusk for a softer look, and
        // scale overall intensity down - these are meant to be a
        // subtle atmospheric touch, not a bloom-blown-out beam.
        float intensity = accumulated * smoothstep(0.0, 0.25, lightDir.y) * 0.35;
        color += lightColor * intensity;
    }
#endif

    gl_FragColor = vec4(color, 1.0);
}
