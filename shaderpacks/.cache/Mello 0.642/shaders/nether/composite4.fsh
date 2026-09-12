#version 330 compatibility

#include "/library/pad.glsl"
#include "/library/bluenoise.glsl"
#include "/library/noise.glsl"

uniform sampler2D depthtex0;
uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex3;

uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform float viewWidth;
uniform float viewHeight;
uniform float far;

in vec2 texcoord;

/* RENDERTARGETS: 4 */
layout(location = 0) out vec4 reflections;

#define SSR_SAMPLES 16 // [1 2 4 8 16 32 64 128 256]
#define SSR_DISTANCE 2.0 // [0.1 0.5 1.0 2.0 4.0 8.0 16.0]
#define SSR_STEP_SIZE SSR_DISTANCE
#define SSR_THICKNESS SSR_DISTANCE
#define SSR_STRENGTH 1.0
#define SSR_STRENGTH_OTHER 0.5
#define SSR_FRESNEL 3.0
#define SSR_FRESNEL_OTHER 0.5
#define SSR_STRENGTH_LESS 0.2
#define SSR_FRESNEL_LESS 1.0

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

    bool isWater = abs(mask - 5.0) < 0.1;
    bool isOther = abs(mask - 2.0) < 0.1 || abs(mask - 11.0) < 0.1 || abs(mask - 20.0) < 0.1 || abs(mask - 25.0) < 0.1 || abs(mask - 29.0) < 0.1 || abs(mask - 41.0) < 0.1;

    if (abs(mask - 14.0) < 0.1) discard;
    
    vec3 viewPos = getViewPos(texcoord, depth);

    vec3 normal = texture(colortex2, texcoord).xyz * 2.0 - 1.0;
    normal = normalize(mat3(gbufferModelView) * normal);

    if (!isWater && !isOther) {
        reflections = vec4(0.0);
        return;
    }

    vec3 viewDir = normalize(viewPos);
    vec3 reflDir = normalize(reflect(viewDir, normal));

    float fresnelExp = isWater ? SSR_FRESNEL : (abs(mask - 25.0) < 0.1 ? SSR_FRESNEL_LESS : SSR_FRESNEL_OTHER);
    float baseStrength = isWater ? SSR_STRENGTH : (abs(mask - 25.0) < 0.1 ? SSR_STRENGTH_LESS : (isOther ? SSR_STRENGTH_OTHER : 0.0));
    float strengthScale = isWater ? SSR_STRENGTH : baseStrength;

    float f = pow(1.0 - max(dot(-viewDir, normal), 0.0), fresnelExp) * strengthScale;

    ivec2 screenCoord = ivec2(gl_FragCoord.xy);
    float noise = getNoise(uvec2(screenCoord));

    vec3 rayPos = viewPos + reflDir * (SSR_STEP_SIZE * noise);

    vec3 hitColor = vec3(0.0);

    bool hit = false;

    ivec2 originCoord = ivec2(texcoord * vec2(viewWidth, viewHeight));

    for (int i = 0; i < SSR_SAMPLES; i++) {
        float traveled = length(rayPos - viewPos);
        float stepSize = SSR_STEP_SIZE * (1.0 + traveled * 0.2);
        stepSize = min(stepSize, SSR_STEP_SIZE * 7.0);

        rayPos += reflDir * stepSize;

        vec3 projected = projectAndDivide(gbufferProjection, rayPos);

        if (projected.z > 1.0)
            break;

        vec2 uv = projected.xy * 0.5 + 0.5;

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
            break;

        ivec2 sampleCoord = ivec2(uv * vec2(viewWidth, viewHeight));

        if (sampleCoord == originCoord)
            continue;

        float sceneDepth = texture(depthtex0, uv).r;

        if (sceneDepth >= 1.0)
            continue;

        vec3 scenePos = getViewPos(uv, sceneDepth);

        float thickness = max(SSR_THICKNESS, stepSize * 0.5);
        thickness *= (1.0 + abs(rayPos.z) * 0.05);
        float diff = scenePos.z - rayPos.z;

        if (diff > 0.0 && diff < thickness) {
            hitColor = texture(colortex0, uv).rgb;
            hit = true;
            break;
        }
    }

    if (!hit) {
        reflections = vec4(0.0);
        return;
    }

    reflections = vec4(hitColor * (abs(mask - 25.0) < 0.1 ? texture(colortex0, texcoord).rgb : vec3(1.0)), f);

    float fogFactor = exp(-3.0 * (1.0 - length(viewPos) / far));
    reflections.a *= 1.0 - clamp(fogFactor, 0.0, 1.0);
}