#version 120

#include "/lib/distort.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowtex1;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 gbufferProjection;
uniform vec3 shadowLightPosition;
uniform float sunAngle;
uniform vec3 fogColor;

const vec3 blocklightColor = vec3(1.0, 0.55, 0.15);
const vec3 skylightColor   = vec3(0.15, 0.25, 0.45);
const vec3 sunlightColor   = vec3(1.0, 0.92, 0.85);
const vec3 ambientColor    = vec3(0.06, 0.07, 0.12);

const bool shadowtex0Nearest = true;
const bool shadowtex1Nearest = true;
const bool shadowcolor0Nearest = true;

#define SHADOW_RADIUS 1
#define SHADOW_RANGE 2
#define MOON_RAY_SAMPLES 10
#define MOON_RAY_STRENGTH 0.04

varying vec2 texcoord;

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position) {
    vec4 homPos = projectionMatrix * vec4(position, 1.0);
    return homPos.xyz / homPos.w;
}

vec3 getShadow(vec3 shadowScreenPos) {
    float transparentShadow = step(shadowScreenPos.z, texture2D(shadowtex0, shadowScreenPos.xy).r);
    if (transparentShadow == 1.0) return vec3(1.0);
    float opaqueShadow = step(shadowScreenPos.z, texture2D(shadowtex1, shadowScreenPos.xy).r);
    if (opaqueShadow == 0.0) return vec3(0.0);
    vec4 shadowColor = texture2D(shadowcolor0, shadowScreenPos.xy);
    return shadowColor.rgb * (1.0 - shadowColor.a);
}

vec3 getSoftShadow(vec4 shadowClipPos) {
    vec3 shadowAccum = vec3(0.0);
    const int samples = SHADOW_RANGE * SHADOW_RANGE * 4;
    for (int x = -SHADOW_RANGE; x < SHADOW_RANGE; x++) {
        for (int y = -SHADOW_RANGE; y < SHADOW_RANGE; y++) {
            vec2 offset = vec2(x, y) * float(SHADOW_RADIUS) / float(SHADOW_RANGE);
            offset /= float(shadowMapResolution);
            vec4 offsetShadowClipPos  = shadowClipPos + vec4(offset, 0.0, 0.0);
            offsetShadowClipPos.z    -= 0.001;
            offsetShadowClipPos.xyz   = distort(offsetShadowClipPos.xyz);
            vec3 shadowNdcPos         = offsetShadowClipPos.xyz / offsetShadowClipPos.w;
            vec3 shadowScreenPos      = shadowNdcPos * 0.5 + 0.5;
            shadowAccum              += getShadow(shadowScreenPos);
        }
    }
    return shadowAccum / float(samples);
}

float getLightRays(vec2 lightScreenPos, int samples) {
    float rays = 0.0;
    vec2 dir = (lightScreenPos - texcoord) / float(samples);
    vec2 samplePos = texcoord;
    for (int i = 0; i < samples; i++) {
        samplePos += dir;
        if (samplePos.x < 0.0 || samplePos.x > 1.0 || samplePos.y < 0.0 || samplePos.y > 1.0) break;
        float depth = texture2D(depthtex0, samplePos).r;
        if (depth < 1.0) rays += 1.0;
    }
    rays = 1.0 - (rays / float(samples));
    float dist = length(lightScreenPos - texcoord);
    rays *= exp(-dist * 3.0);
    return clamp(rays, 0.0, 1.0);
}

void main() {
    vec4 color = texture2D(colortex0, texcoord);
    color.rgb = pow(color.rgb, vec3(1.0));
    float depth = texture2D(depthtex0, texcoord).r;
    if (depth == 1.0) { gl_FragData[0] = color; return; }

    vec4 lightmapSample = texture2D(colortex1, texcoord);
    vec2 lightmap = lightmapSample.xy;
    float isWater = lightmapSample.z;

    vec3 ndcPos        = vec3(texcoord, depth) * 2.0 - 1.0;
    vec3 viewPos       = projectAndDivide(gbufferProjectionInverse, ndcPos);
    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
    vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);

    vec3 shadow = getSoftShadow(shadowClipPos);

    float timeOfDay = clamp(sin(sunAngle * 3.14159 * 2.0) * 3.0, 0.0, 1.0);
    float isNight   = 1.0 - timeOfDay;
    bool isNether   = fogColor.r > 0.4 && fogColor.g < 0.2;

    vec3 nightColor = vec3(0.15, 0.18, 0.35);
    vec3 lightColor = mix(nightColor, sunlightColor, timeOfDay);

    vec3 blocklight = lightmap.x * blocklightColor;
    float nightSky  = clamp(sin(sunAngle * 3.14159 * 2.0 + 3.14159) * 0.5 + 0.5, 0.75, 1.0);
    vec3 skylight   = lightmap.y * skylightColor * mix(nightSky, 1.0, timeOfDay);
    vec3 ambient    = isNether ? vec3(0.3, 0.08, 0.05) : ambientColor + vec3(0.02, 0.02, 0.03) * isNight;
    vec3 sunlight   = lightColor * shadow * lightmap.y;

    vec3 litColor = color.rgb * (blocklight + skylight + ambient + sunlight);
    color.rgb = mix(litColor, color.rgb, isWater);
    color.rgb = max(color.rgb, vec3(0.05) * isNight);

    vec4 lightClipPos   = gbufferProjection * vec4(shadowLightPosition, 1.0);
    vec3 lightNdcPos    = lightClipPos.xyz / lightClipPos.w;
    vec2 lightScreenPos = lightNdcPos.xy * 0.5 + 0.5;

    float moonRays = getLightRays(lightScreenPos, MOON_RAY_SAMPLES) * isNight * lightmap.y * MOON_RAY_STRENGTH;
    color.rgb += vec3(0.7, 0.8, 1.0) * moonRays;

    gl_FragData[0] = color;
}