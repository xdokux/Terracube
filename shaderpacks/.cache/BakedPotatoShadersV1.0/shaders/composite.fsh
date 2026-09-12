#version 120

#include "/lib/settings.glsl"
#include "/lib/math.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D depthtex2;
uniform float rainStrength;
uniform int isEyeInWater;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;

varying vec2 vTexCoord;

#include "/lib/overworld_water_reflections.glsl"

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16F;
*/
const bool colortex0Clear = true;
const bool colortex1Clear = true;
const bool colortex2Clear = true;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex3Clear = true;
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

vec3 brightPass(vec3 color) {
    float brightness = luminance(color);
    float mask = smoothstep(0.88, 1.65, brightness);
    return color * mask;
}

float linearizeDepth(float depth) {
    float clipDepth = depth * 2.0 - 1.0;
    return (2.0 * near * far) / max(far + near - clipDepth * (far - near), 0.0001);
}

void main() {
    vec3 sourceScene = texture2D(colortex0, vTexCoord).rgb;
    vec3 scene = sourceScene;

    // One metadata lookup for all pixels; the expensive trace runs only where
    // the top surface of Overworld water was explicitly written.
    vec4 waterData = texture2D(colortex3, vTexCoord);
    if (waterData.b > 0.0001 && isEyeInWater == 0) {
        scene = applyOverworldWaterReflections(scene, vTexCoord, waterData);
    }

    float rain = saturate(rainStrength);
    if (rain > 0.010 && isEyeInWater == 0) {
        // depthtex2 excludes transparent geometry and the hand, keeping clouds,
        // precipitation, held items and nearby geometry perfectly sharp.
        float depth = texture2D(depthtex2, vTexCoord).r;
        if (depth < 0.9995) {
            float worldDistance = linearizeDepth(depth);
            float distantScene = smoothstep(far * 0.36, far * 0.86, worldDistance);
            if (distantScene > 0.0) {
                vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
                vec2 humidOffset = texel * vec2(0.72, 0.48) * (0.70 + distantScene * 0.55);
                vec3 humidSample = scene * 0.50 +
                                   texture2D(colortex0, vTexCoord + humidOffset).rgb * 0.25 +
                                   texture2D(colortex0, vTexCoord - humidOffset).rgb * 0.25;
                scene = mix(scene, humidSample, rain * distantScene * 0.203);
            }
        }
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
