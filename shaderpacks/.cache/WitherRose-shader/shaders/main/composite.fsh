#version 120
/* 动态模糊 */
#include "/lib/dither.glsl"

varying vec2 TexCoords;

uniform float viewWidth, viewHeight, frameTimeCounter;
uniform vec3 cameraPosition, previousCameraPosition;
uniform mat4 gbufferPreviousProjection, gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView, gbufferModelViewInverse;
uniform sampler2D colortex0;
uniform sampler2D depthtex1;

const float DEPTH_THRESHOLD = 0.66; // 深度阈值
#include "/lib/settings.glsl"
#define MOTION_BLUR_STRENGTH 0.6    // 强度
#define MOTION_BLUR_SAMPLES 8       // 采样次数

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

vec3 MotionBlur(vec3 color, float z, float dither) {
    if (z <= DEPTH_THRESHOLD) return color;

    vec4 currentPos = vec4(TexCoords, z, 1.0) * 2.0 - 1.0;
    vec4 viewPos = gbufferProjectionInverse * currentPos;
    viewPos = gbufferModelViewInverse * viewPos;
    viewPos /= viewPos.w;

    vec3 cameraOffset = cameraPosition - previousCameraPosition;
    vec4 prevPos = gbufferPreviousProjection * gbufferPreviousModelView * (viewPos + vec4(cameraOffset, 0.0));
    prevPos /= prevPos.w;
    vec2 velocity = (currentPos - prevPos).xy;
    velocity = velocity / (1.0 + length(velocity)) * MOTION_BLUR_STRENGTH;

    vec3 mblur = vec3(0.0);
    float totalWeight = 0.0;
    for (int i = 0; i < MOTION_BLUR_SAMPLES; i++) {
        float t = (float(i) + dither) / float(MOTION_BLUR_SAMPLES - 1);
        vec2 offset = velocity * (t - 0.5);
        vec2 sampleCoord = TexCoords + offset;

        vec3 sampleColor = texture2D(colortex0, sampleCoord).rgb;
        float noise = random(sampleCoord * frameTimeCounter);
        float weight = mix(0.5, 1.0, noise);

        mblur += sampleColor * weight;
        totalWeight += weight;
    }

    return mblur / totalWeight;
}

void main() {
    vec3 color = texture2D(colortex0, TexCoords).rgb;
    float z = texture2D(depthtex1, TexCoords).x;
    float dither = Bayer64(gl_FragCoord.xy) + random(TexCoords * frameTimeCounter);

    #if MOTIONBLUR == 1
    color = MotionBlur(color, z, dither);
    #endif

    gl_FragData[0] = vec4(color, 1.0);
}