#version 120

#define SHADOW_DARKNESS 0.35
#define SHADOW_PCF_RADIUS 1.0
#define COLORED_SHADOW_STRENGTH 1.0
#define BLOCK_LIGHT_BRIGHTNESS 1.4
#define WATER_RIPPLE_STRENGTH 0.04 // Ripple normal strength - higher = choppier looking water [0.0 0.02 0.03 0.04 0.05 0.07 0.1]

uniform sampler2D tex;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform vec3 shadowLightPosition;
uniform float frameTimeCounter;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 normal;
varying vec4 shadowPos;
varying vec2 waveCoord;

vec3 sampleShadowTap(vec2 uv, float compareDepth) {
    float bias = 0.0008;

    float solidDepth = texture2D(shadowtex1, uv).r;
    if (compareDepth - bias > solidDepth) {
        return vec3(SHADOW_DARKNESS);
    }

    float fullDepth = texture2D(shadowtex0, uv).r;
    if (compareDepth - bias > fullDepth) {
        vec3 tint = texture2D(shadowcolor0, uv).rgb;
        return mix(vec3(1.0), tint, COLORED_SHADOW_STRENGTH);
    }

    return vec3(1.0);
}

/* RENDERTARGETS: 0,1 */
void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;

    vec3 shadowScreen = shadowPos.xyz / shadowPos.w;
    shadowScreen = shadowScreen * 0.5 + 0.5;

    vec3 shadowResult = vec3(1.0);
    if (shadowScreen.x >= 0.0 && shadowScreen.x <= 1.0 &&
        shadowScreen.y >= 0.0 && shadowScreen.y <= 1.0 &&
        shadowScreen.z >= 0.0 && shadowScreen.z <= 1.0) {

        float texelSize = (1.0 / 2048.0) * SHADOW_PCF_RADIUS;
        vec3 sum = vec3(0.0);
        sum += sampleShadowTap(shadowScreen.xy + vec2(-texelSize, -texelSize), shadowScreen.z);
        sum += sampleShadowTap(shadowScreen.xy + vec2( texelSize, -texelSize), shadowScreen.z);
        sum += sampleShadowTap(shadowScreen.xy + vec2(-texelSize,  texelSize), shadowScreen.z);
        sum += sampleShadowTap(shadowScreen.xy + vec2( texelSize,  texelSize), shadowScreen.z);
        shadowResult = sum * 0.25;
    }

    vec3 n = normalize(normal);

    // Cheap animated ripple in world space (doesn't swim with camera).
    float wave1 = sin(waveCoord.x * 1.2 + frameTimeCounter * 1.3) * WATER_RIPPLE_STRENGTH;
    float wave2 = cos(waveCoord.y * 1.1 + frameTimeCounter * 1.7) * WATER_RIPPLE_STRENGTH;
    n = normalize(n + vec3(wave1, wave2, 0.0));

    float NdotL = clamp(dot(n, normalize(shadowLightPosition)), 0.0, 1.0);

    // Same block-light/sky-light split as gbuffers_terrain.fsh - see
    // that file for the full explanation of why this was necessary.
    float blockLight = clamp(lmcoord.x, 0.0, 1.0);
    float skyLight = clamp(lmcoord.y, 0.0, 1.0);

    vec3 blockLightColor = vec3(1.0, 0.75, 0.45);
    vec3 skyLightColor = vec3(0.8, 0.87, 1.0);

    vec3 blockContribution = blockLightColor * pow(blockLight, 1.5) * BLOCK_LIGHT_BRIGHTNESS;
    vec3 sunContribution = skyLightColor * skyLight * NdotL * shadowResult;
    vec3 ambientFloor = vec3(0.05);

    vec3 lighting = ambientFloor + blockContribution + sunContribution;
    vec3 finalColor = albedo.rgb * lighting;

    gl_FragData[0] = vec4(clamp(finalColor, 0.0, 1.0), albedo.a);
    // alpha = 1.0 -> tells composite.fsh "this pixel should get a sky reflection"
    gl_FragData[1] = vec4(n * 0.5 + 0.5, 1.0);
}
