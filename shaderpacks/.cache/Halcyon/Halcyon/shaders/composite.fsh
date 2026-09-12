#version 120

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex1;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;

uniform vec3 fogColor;
uniform vec3 shadowLightPosition;
uniform float near;
uniform float far;
uniform float rainStrength;
uniform int isEyeInWater;

varying vec2 texcoord;

// --- tunable constants ---
const int VL_STEPS = 16;
const float VL_MAX_DIST = 80.0;   // stop marching this far from the camera (perf guard)
const float VL_STRENGTH = 0.06;

float linearizeDepth(float d) {
    return (2.0 * near) / (far + near - d * (far - near));
}

float hash12(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 reconstructViewPos(float depth) {
    vec4 clipPos = vec4(texcoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPosH = gbufferProjectionInverse * clipPos;
    return viewPosH.xyz / viewPosH.w;
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).r;

    vec3 fragViewPos = reconstructViewPos(depth);
    float travelDist = min(length(fragViewPos), VL_MAX_DIST);
    vec3 rayDir = normalize(fragViewPos);

    // Per-pixel jitter so the ray step count doesn't show up as visible banding
    float jitter = hash12(gl_FragCoord.xy);
    float stepLen = travelDist / float(VL_STEPS);

    vec3 sunTint = mix(vec3(1.0, 0.9, 0.7), vec3(0.5, 0.55, 0.65), rainStrength);
    float scatter = 0.0;

    for (int i = 0; i < VL_STEPS; i++) {
        float t = (float(i) + jitter) * stepLen;
        vec3 samplePos = rayDir * t; // view-space position along the ray

        vec4 worldH = gbufferModelViewInverse * vec4(samplePos, 1.0); // camera-relative world pos
        vec4 shadowClip = shadowProjection * shadowModelView * worldH;
        vec3 shadowNDC = shadowClip.xyz / shadowClip.w * 0.5 + 0.5;

        if (shadowNDC.x < 0.0 || shadowNDC.x > 1.0 || shadowNDC.y < 0.0 || shadowNDC.y > 1.0 || shadowNDC.z > 1.0) {
            scatter += 1.0; // outside shadow map coverage - assume lit rather than dark banding
            continue;
        }

        float shadowDepth = texture2D(shadowtex1, shadowNDC.xy).r;
        if (shadowNDC.z - 0.001 <= shadowDepth) {
            scatter += 1.0;
        }
    }
    scatter /= float(VL_STEPS);

    color += scatter * sunTint * VL_STRENGTH * clamp(travelDist / VL_MAX_DIST + 0.15, 0.0, 1.0);

    // --- distance fog on top, same technique as before ---
    if (depth < 1.0) {
        float linDepth = linearizeDepth(depth);
        float fogFactor = clamp((linDepth - 0.15) / 0.6, 0.0, 1.0);
        fogFactor *= fogFactor;
        if (isEyeInWater == 1) fogFactor = clamp(fogFactor * 3.0, 0.0, 1.0);
        color = mix(color, fogColor, fogFactor);
    }

    gl_FragColor = vec4(color, 1.0);
}
