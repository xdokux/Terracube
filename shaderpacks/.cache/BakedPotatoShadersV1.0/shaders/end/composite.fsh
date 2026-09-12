#version 120

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/end_sky.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

varying vec2 vTexCoord;

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16F;
*/
const bool colortex0Clear = true;
const bool colortex1Clear = true;
const bool colortex2Clear = true;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

vec3 brightPass(vec3 color) {
    float brightness = luminance(color);
    float mask = smoothstep(0.88, 1.65, brightness);
    return color * mask;
}

void main() {
    vec3 sourceScene = texture2D(colortex0, vTexCoord).rgb;
    vec3 scene = sourceScene;
    float depth = texture2D(depthtex0, vTexCoord).r;

    if (depth > 0.999999) {
        vec4 clipDirection = vec4(vTexCoord * 2.0 - 1.0, 1.0, 1.0);
        vec4 viewDirection = gbufferProjectionInverse * clipDirection;
        vec3 worldDirection = safeNormalize(mat3(gbufferModelViewInverse) * viewDirection.xyz);
        scene = getEndSpaceSky(worldDirection);
    }

    vec3 bloom = vec3(0.0);

#if BLOOM_QUALITY > 0
    vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    vec2 radius = texel * 2.2;
    bloom += brightPass(sourceScene) * 0.28;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2( radius.x, 0.0)).rgb) * 0.18;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2(-radius.x, 0.0)).rgb) * 0.18;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2(0.0,  radius.y)).rgb) * 0.18;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2(0.0, -radius.y)).rgb) * 0.18;
#if BLOOM_QUALITY == 2
    vec2 diagonal = radius * 0.78;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2( diagonal.x,  diagonal.y)).rgb) * 0.09;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2(-diagonal.x,  diagonal.y)).rgb) * 0.09;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2( diagonal.x, -diagonal.y)).rgb) * 0.09;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2(-diagonal.x, -diagonal.y)).rgb) * 0.09;
    bloom *= 0.735;
#endif
#endif

    gl_FragData[0] = vec4(scene + bloom * BLOOM_STRENGTH, 1.0);
}

/* RENDERTARGETS: 1 */
