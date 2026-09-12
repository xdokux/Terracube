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
    vec4 light = texture2D(lightmap, lmcoord);

    vec3 shadowScreen = shadowPos.xyz / shadowPos.w;
    shadowScreen = shadowScreen * 0.5 + 0.5;

    float shadow = 1.0;
    if (shadowScreen.x >= 0.0 && shadowScreen.x <= 1.0 &&
        shadowScreen.y >= 0.0 && shadowScreen.y <= 1.0 &&
        shadowScreen.z >= 0.0 && shadowScreen.z <= 1.0) {
        float bias = 0.0015;
        float shadowMapDepth = texture2D(shadowtex1, shadowScreen.xy).r;
        shadow = (shadowScreen.z - bias > shadowMapDepth) ? SHADOW_DARKNESS : 1.0;
    }

    vec3 n = normalize(normal);
    float NdotL = clamp(dot(n, normalize(shadowLightPosition)), 0.0, 1.0);
    vec3 finalColor = albedo.rgb * light.rgb * (0.35 + 0.65 * NdotL * shadow);

    gl_FragData[0] = vec4(finalColor, albedo.a);
    // alpha = 1.0 -> tells composite.fsh "this pixel should get SSR"
    gl_FragData[1] = vec4(n * 0.5 + 0.5, 1.0);
}
