#version 120

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/nether_sky.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform int isEyeInWater;
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
#if BLOOM_QUALITY > 0
    vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    vec2 radius = texel * 2.2;
    vec3 lowerScene = texture2D(colortex0, vTexCoord - vec2(0.0, radius.y)).rgb;
#else
    vec3 lowerScene = sourceScene;
#endif

    if (depth > 0.999999) {
        vec4 clipDirection = vec4(vTexCoord * 2.0 - 1.0, 1.0, 1.0);
        vec4 viewDirection = gbufferProjectionInverse * clipDirection;
        vec3 worldDirection = safeNormalize(mat3(gbufferModelViewInverse) * viewDirection.xyz);
        scene = getNetherVolcanicSky(worldDirection);
    }

    if (isEyeInWater == 0) {
        float heatLuminance = luminance(lowerScene);
        float heatWarmth = max(lowerScene.r - lowerScene.g * 0.72 - lowerScene.b * 0.20, 0.0);
        float heatMask = smoothstep(0.72, 1.48, heatLuminance) *
                         smoothstep(0.10, 0.56, heatWarmth);
#if BLOOM_QUALITY > 0
        heatMask *= 1.0 - smoothstep(0.72, 1.24, luminance(sourceScene));
#endif
        if (heatMask > 0.001) {
            float risePhase = vTexCoord.y * viewHeight * 0.108 - frameTimeCounter * 3.0;
            vec2 heatOffset = vec2(
                sin(risePhase + vTexCoord.x * viewWidth * 0.017),
                cos(risePhase * 0.61 - vTexCoord.x * viewWidth * 0.011)
            ) * vec2(0.66 / viewWidth, 0.10 / viewHeight);
            vec3 heatedScene = texture2D(colortex0, vTexCoord + heatOffset).rgb;
            scene = mix(scene, heatedScene, heatMask * 0.10);
        }

    }

    if (isEyeInWater == 0 && depth <= 0.999999) {
        float distantMask = smoothstep(0.968, 0.9988, depth) *
                            (1.0 - smoothstep(0.99965, 1.0, depth));
        if (distantMask > 0.0) {
            vec4 weights = getNetherBiomeWeights();
            vec2 aspectCoord = vTexCoord * vec2(viewWidth / max(viewHeight, 1.0), 1.0);
            vec2 particleCoord = aspectCoord * vec2(118.0, 82.0) +
                                 vec2(frameTimeCounter * 0.34, -frameTimeCounter * 0.51);
            vec2 cell = floor(particleCoord);
            vec2 local = fract(particleCoord);
            float randomValue = netherHash12(cell);
            vec2 center = vec2(netherHash12(cell + 5.2), netherHash12(cell + 17.9));
            vec2 particleDelta = local - center;
            float particleShape = 1.0 - smoothstep(0.025, 0.115, length(particleDelta));
            float ash = particleShape * step(0.972, randomValue) * getNetherAshAmount(weights);
            scene += vec3(0.055, 0.047, 0.043) * ash * distantMask * 0.34;
        }
    }

    vec3 bloom = vec3(0.0);

#if BLOOM_QUALITY > 0
    bloom += brightPass(sourceScene) * 0.28;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2( radius.x, 0.0)).rgb) * 0.18;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2(-radius.x, 0.0)).rgb) * 0.18;
    bloom += brightPass(texture2D(colortex0, vTexCoord + vec2(0.0,  radius.y)).rgb) * 0.18;
    bloom += brightPass(lowerScene) * 0.18;
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
