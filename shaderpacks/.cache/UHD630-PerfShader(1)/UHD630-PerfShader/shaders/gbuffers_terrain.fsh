#version 120

#define SHADOW_DARKNESS 0.35 // Shadow darkness [0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6]

uniform sampler2D tex;
uniform sampler2D lightmap;
uniform sampler2D shadowtex1;
uniform vec3 shadowLightPosition;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 normal;
varying vec4 shadowPos;

/* RENDERTARGETS: 0,1 */
void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;
    if (albedo.a < 0.1) discard;

    vec4 light = texture2D(lightmap, lmcoord);

    // ---- 2x2 PCF shadow lookup ----
    // Only 4 taps (vs. 1 before) - still cheap, but smooths out the
    // jagged/blobby edges the single-tap version had on small casters.
    vec3 shadowScreen = shadowPos.xyz / shadowPos.w;
    shadowScreen = shadowScreen * 0.5 + 0.5;

    float shadow = 1.0;
    if (shadowScreen.x >= 0.0 && shadowScreen.x <= 1.0 &&
        shadowScreen.y >= 0.0 && shadowScreen.y <= 1.0 &&
        shadowScreen.z >= 0.0 && shadowScreen.z <= 1.0) {

        float bias = 0.0006; // tighter now that normal-offset bias handles most of the work
        float texelSize = 1.0 / 2048.0;
        float litSamples = 0.0;

        litSamples += (shadowScreen.z - bias > texture2D(shadowtex1, shadowScreen.xy + vec2(-texelSize, -texelSize)).r) ? 0.0 : 1.0;
        litSamples += (shadowScreen.z - bias > texture2D(shadowtex1, shadowScreen.xy + vec2( texelSize, -texelSize)).r) ? 0.0 : 1.0;
        litSamples += (shadowScreen.z - bias > texture2D(shadowtex1, shadowScreen.xy + vec2(-texelSize,  texelSize)).r) ? 0.0 : 1.0;
        litSamples += (shadowScreen.z - bias > texture2D(shadowtex1, shadowScreen.xy + vec2( texelSize,  texelSize)).r) ? 0.0 : 1.0;

        float litFraction = litSamples * 0.25;
        shadow = mix(SHADOW_DARKNESS, 1.0, litFraction);
    }

    vec3 n = normalize(normal);
    float NdotL = clamp(dot(n, normalize(shadowLightPosition)), 0.0, 1.0);
    float directLight = NdotL * shadow;

    vec3 finalColor = albedo.rgb * light.rgb * (0.35 + 0.65 * directLight);

    gl_FragData[0] = vec4(finalColor, albedo.a);
    // colortex1: pack view-space normal into 0-1, alpha = 0 -> not reflective
    gl_FragData[1] = vec4(n * 0.5 + 0.5, 0.0);
}
