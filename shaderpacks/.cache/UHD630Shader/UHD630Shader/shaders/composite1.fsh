#version 120
/* DRAWBUFFERS:0 */

#include "/lib/common.glsl"

varying vec2 texcoord;

uniform sampler2D colortex0; // scene color
uniform sampler2D colortex1; // normal.rgb + reflective-mask.a
uniform sampler2D colortex2; // godray mask (R channel)
uniform sampler2D depthtex0;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

// SSR_STEPS is swapped by shader.properties profiles (LOW/MEDIUM/HIGH).
#define SSR_STEPS 6        // [6 12 20 30] Reflection raymarch steps. Lower = faster.
#define SSR_MAX_DIST 16.0  // [8.0 16.0 24.0 32.0] Max ray travel distance in blocks.
const float SSR_STEP_SIZE = 1.0;

// Very simple linear-step screen-space raymarch. Returns reflected color, or
// vec3(-1.0) if the ray missed everything (caller should fall back to base color).
// UNCERTAINTY: this is a minimal reference SSR - no binary-search refinement step,
// no roughness blur, no edge fade. Expect visible stepping/aliasing on reflections;
// that trade-off is intentional here to keep the cost low enough for UHD 630, but
// you WILL want to tune SSR_STEP_SIZE and SSR_STEPS in-game to your taste.
vec3 screenSpaceReflection(vec3 viewPos, vec3 normalVec) {
    vec3 reflectDir = reflect(normalize(viewPos), normalize(normalVec));
    vec3 rayPos = viewPos;

    for (int i = 0; i < SSR_STEPS; i++) {
        rayPos += reflectDir * SSR_STEP_SIZE;
        if (length(rayPos - viewPos) > SSR_MAX_DIST) break;

        vec4 sampleClip = gbufferProjection * vec4(rayPos, 1.0);
        if (sampleClip.w <= 0.0) break;
        vec2 sampleUV = (sampleClip.xy / sampleClip.w) * 0.5 + 0.5;

        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) break;

        float sampleDepth = texture2D(depthtex0, sampleUV).r;
        vec3 sampleViewPos = reconstructViewPos(sampleUV, sampleDepth, gbufferProjectionInverse);

        // View space looks down -Z; a hit is when the ray has gone "behind" existing geometry.
        if (rayPos.z < sampleViewPos.z && sampleViewPos.z - rayPos.z < 0.5) {
            return texture2D(colortex0, sampleUV).rgb;
        }
    }
    return vec3(-1.0); // miss
}

void main() {
    vec3 baseColor   = texture2D(colortex0, texcoord).rgb;
    vec4 normalData  = texture2D(colortex1, texcoord);
    float godray     = texture2D(colortex2, texcoord).r;
    float depth      = texture2D(depthtex0, texcoord).r;

    vec3 finalColor = baseColor;

    if (normalData.a > 0.5) { // reflective surface (water) per gbuffers_water.fsh
        vec3 viewPos   = reconstructViewPos(texcoord, depth, gbufferProjectionInverse);
        vec3 normalVec = normalize(normalData.rgb * 2.0 - 1.0);
        vec3 reflection = screenSpaceReflection(viewPos, normalVec);

        if (reflection.r >= 0.0) {
            finalColor = mix(baseColor, reflection, 0.5);
        }
        // else: ray missed - keep plain water color rather than paying for a sky-color fallback sample
    }

    finalColor += godray * vec3(1.0, 0.95, 0.8);

    gl_FragData[0] = vec4(finalColor, 1.0);
}
