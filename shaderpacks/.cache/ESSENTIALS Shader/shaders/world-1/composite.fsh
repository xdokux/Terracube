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
uniform vec3 fogColor;
uniform float far;

const bool shadowtex0Nearest = true;
const bool shadowtex1Nearest = true;
const bool shadowcolor0Nearest = true;

#define SHADOW_RADIUS 1
#define SHADOW_RANGE 2

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

void main() {
    vec4 color = texture2D(colortex0, texcoord);

    float depth = texture2D(depthtex0, texcoord).r;
    if (depth == 1.0) {
        gl_FragData[0] = color;
        return;
    }

    vec4 lightmapSample = texture2D(colortex1, texcoord);
    vec2 lightmap = lightmapSample.xy;

    vec3 ndcPos        = vec3(texcoord, depth) * 2.0 - 1.0;
    vec3 viewPos       = projectAndDivide(gbufferProjectionInverse, ndcPos);
    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
    vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);

    vec3 shadow = getSoftShadow(shadowClipPos);

    float lightStrength = pow(lightmap.x, 0.5);
    color.rgb *= (0.5 + lightStrength * 1.5) * mix(shadow, vec3(1.0), 0.5);
    color.rgb  = max(color.rgb, vec3(0.03));

    float dist      = length(viewPos) / far;
    float fogFactor = exp(-8.0 * (1.0 - dist));
    color.rgb = mix(color.rgb, fogColor, clamp(fogFactor, 0.0, 1.0));

    gl_FragData[0] = color;
}
