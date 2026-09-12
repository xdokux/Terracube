#version 330 compatibility

#include "/library/pad.glsl"
#include "/library/time.glsl"
#include "/library/sky.glsl"

uniform sampler2D depthtex0;
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

uniform int isEyeInWater;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;

in vec2 texcoord;

/* RENDERTARGETS: 4 */
layout(location = 0) out vec4 reflections;

// --- [ Reflections ] ---
#define SSR_STEPS 16 // [8 16 32]
#define SSR_DISTANCE 4.0 // [1.0 2.0 4.0 8.0 16.0]
#define SSR_STEP_SIZE SSR_DISTANCE
#define SSR_THICKNESS SSR_DISTANCE
#define SSR_STRENGTH 1.0
#define SSR_STRENGTH_OTHER 0.5
#define SSR_FRESNEL 3.0
#define SSR_FRESNEL_OTHER 2.0

float hash12(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float waveNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec3 getViewPos(vec2 uv, float depth) {
    vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
    return projectAndDivide(gbufferProjectionInverse, ndc);
}

void main() {
    float depth = texture(depthtex0, texcoord).r;

    if (depth >= 1.0) {
        reflections = vec4(0.0);
        return;
    }

    float mask = texture(colortex3, texcoord).r;

    bool isWater = abs(mask - 5.0) < 0.01;
    bool isOther = abs(mask - 2.0) < 0.01 || abs(mask - 11.0) < 0.01;

    if (!isWater && !isOther) {
        reflections = vec4(0.0);
        return;
    }

    calculateTimeBlend();

    float light = pow(texture(colortex1, texcoord).g, 2.0);

    vec3 viewPos = getViewPos(texcoord, depth);

    vec3 normal = texture(colortex2, texcoord).xyz * 2.0 - 1.0;
    normal = normalize(mat3(gbufferModelView) * normal);

    if (isWater) {
        normal = normalize(normal);
    }

    vec3 viewDir = normalize(viewPos);
    vec3 reflDir = normalize(reflect(viewDir, normal));

    float fresnelExp = isWater ? SSR_FRESNEL : SSR_FRESNEL_OTHER;
    float strengthScale = isWater ? SSR_STRENGTH : SSR_STRENGTH_OTHER;

    float f = pow(1.0 - max(dot(-viewDir, normal), 0.0), fresnelExp) * strengthScale;

    vec3 rayPos = viewPos;

    vec3 hitColor = vec3(0.0);
    vec3 skyColor = calculateSkyGradient(reflDir) + calculateMie(reflDir);

    bool hit = false;

    for (int i = 0; i < SSR_STEPS; i++) {

        rayPos += reflDir * SSR_STEP_SIZE;

        vec3 projected = projectAndDivide(gbufferProjection, rayPos);

        if (projected.z > 1.0)
            break;

        vec2 uv = projected.xy * 0.5 + 0.5;

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
            break;

        float sceneDepth = texture(depthtex0, uv).r;

        if (sceneDepth >= 1.0)
            continue;

        vec3 scenePos = getViewPos(uv, sceneDepth);

        float thickness = SSR_THICKNESS * (1.0 + abs(rayPos.z) * 0.02);
        float diff = scenePos.z - rayPos.z;

        if (diff > 0.0 && diff < thickness) {
            hitColor = texture(colortex0, uv).rgb;
            hit = true;
            break;
        }
    }

    vec3 skyColor2 = (calculateSkyGradient(reflDir) + calculateMie(reflDir));
    vec3 finalRefl = hit ? hitColor : (isWater && isEyeInWater == 1 ? vec3(0.0) : skyColor2 * light);

    reflections = vec4(finalRefl, hit ? f : f * light);
}