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

#define SSR_STEPS 16 // [1 2 4 8 16 32 64 128 256]
#define SSR_DISTANCE 4.0 // [0.1 0.5 1.0 2.0 4.0 8.0 16.0 32.0 64.0]
#define SSR_STEP_SIZE SSR_DISTANCE
#define SSR_THICKNESS SSR_DISTANCE
#define SSR_STRENGTH 1.0
#define SSR_STRENGTH_OTHER 0.5
#define SSR_FRESNEL 3.0
#define SSR_FRESNEL_OTHER 2.0

#define WATER_WAVE_STRENGTH 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

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

    calculateTimeBlend();

    float light = pow(texture(colortex1, texcoord).g, 2.0);

    vec3 viewPos = getViewPos(texcoord, depth);

    vec3 normal = texture(colortex2, texcoord).xyz * 2.0 - 1.0;
    normal = normalize(mat3(gbufferModelView) * normal);

    float topFace = isWater ? 1.0 : max(0.0, dot(mat3(gbufferModelViewInverse) * normal, vec3(0.0, 1.0, 0.0)));
    float wetness = rainStrength * smoothstep(0.2, 0.6, light) * topFace;

    vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos + cameraPosition;

    float puddle = !isWater ? smoothstep(0.5 - rainStrength * 0.25, 0.55, waveNoise(worldPos.xz * 0.3)) * wetness : 0.0;

    if (!isWater && !isOther && puddle < 0.001) {
        reflections = vec4(0.0);
        return;
    }

    if (isWater) {
        float scale = 1.0 / 2.0;

        vec2 p = worldPos.xz * scale;

        if (WATER_WAVE_STRENGTH > 0.0) {

            float t = frameTimeCounter;

            p += vec2(t);

            float n = waveNoise(p);
            float n2 = waveNoise(p * 1.7 + 4.0 - vec2(t * 0.5, t * 0.3));

            vec2 offset = vec2(n, n2) * 2.0 - 1.0;

            normal.xz += offset * 0.03 * WATER_WAVE_STRENGTH * light;
            normal = normalize(normal);
        }
    }

    vec3 viewDir = normalize(viewPos);
    vec3 reflDir = normalize(reflect(viewDir, normal));

    float fresnelExp = isWater ? SSR_FRESNEL : SSR_FRESNEL_OTHER;
    float baseStrength = isWater ? SSR_STRENGTH : (isOther ? SSR_STRENGTH_OTHER : 0.0);
    float strengthScale = isWater ? SSR_STRENGTH : mix(baseStrength, SSR_STRENGTH * 0.7, puddle);

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

    vec3 skyColor2 = isEyeInWater == 1 ? vec3(0.0) : (calculateSkyGradient(reflDir) + calculateMie(reflDir));
    vec3 finalReflection = hit ? hitColor : (isWater && isEyeInWater == 1 ? vec3(0.0) : skyColor2 * light);

    reflections = vec4(finalReflection, (isEyeInWater == 1 && !hit) ? 0.0 : (hit ? f : f * light));
}