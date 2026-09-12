#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform sampler2D texture;
uniform sampler2D depthtex1;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float viewWidth, viewHeight;
uniform int isEyeInWater;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 normalV;
varying vec3 viewPos;
varying vec3 worldPos;
varying float isWater;

// Wave normal: three octaves, fine sampling distance for crisp detail
float waveHeight(vec2 p, float t) {
    return noise3(vec3(p * 0.35, t * 0.45))
         + 0.45 * noise3(vec3(p * 1.6, t * 0.8))
         + 0.22 * noise3(vec3(p * 5.2 + vec2(t * 0.3, 0.0), t * 1.3));
}
vec3 waveNormal(vec2 p, float t) {
    float e = 0.12;
    float h0 = waveHeight(p, t);
    float hx = waveHeight(p + vec2(e, 0.0), t);
    float hz = waveHeight(p + vec2(0.0, e), t);
    return normalize(vec3(h0 - hx, e * 2.2, h0 - hz));
}

void main() {
    vec4 albedo = texture2D(texture, texcoord) * glcolor;
    vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

    vec3 sunDirV = normalize(shadowLightPosition);
    vec3 viewDir = normalize(-viewPos);

    if (isWater > 0.5) {
        // --- depth-based absorption ---
        float solidDepth = texture2D(depthtex1, screenUV).r;
        vec4 solidNdc = gbufferProjectionInverse * vec4(vec3(screenUV, solidDepth) * 2.0 - 1.0, 1.0);
        float waterDist = max(length(solidNdc.xyz / solidNdc.w) - length(viewPos), 0.0);

        vec3 absorb = vec3(0.35, 0.09, 0.06) * WATER_ABSORPTION;
        vec3 trans = exp(-absorb * waterDist);

        // Water body brightness follows actual light: sky + torch. In an
        // unlit cave the water goes near-black instead of glowing blue.
        float waterLight = lmcoord.y * lmcoord.y + lmcoord.x * lmcoord.x * 0.5 + 0.008;
        vec3 deepColor = vec3(0.015, 0.10, 0.14) * clamp(waterLight, 0.0, 1.2);
        // Torch-lit cave water leans warm-teal, not sky-cyan
        deepColor = mix(deepColor, vec3(0.05, 0.06, 0.05), lmcoord.x * (1.0 - lmcoord.y) * 0.6);
        vec3 waterCol = mix(deepColor, deepColor * 2.2, trans.g);

        // --- waves & fresnel ---
        vec3 wn = waveNormal(worldPos.xz, frameTimeCounter);
        vec3 nV = normalize(mix(normalV, normalize(gl_NormalMatrix * wn), 0.65));
        float fresnel = pow(1.0 - max(dot(viewDir, nV), 0.0), 5.0);
        fresnel = mix(0.03, 1.0, fresnel);

        // Sky reflection through the same atmosphere model
        vec3 reflV = reflect(-viewDir, nV);
        mat3 mvInv = mat3(gbufferModelView);
        vec3 reflW = reflV * mvInv; // view->world (transpose of ortho matrix)
        reflW.y = abs(reflW.y) * 0.8 + 0.05;
        vec3 sunW = normalize(sunPosition) * mvInv;
        vec3 tr;
        // Match the HDR scale used by deferred's sky (×3 SUN_INTENSITY)
        vec3 skyRef = skyScatter(normalize(reflW), normalize(sunW), HAZE_HUMIDITY * 0.5 + rainStrength, tr)
                    * 3.0 * SUN_INTENSITY * lmcoord.y;

        // Sun glitter
        float spec = pow(max(dot(reflV, sunDirV), 0.0), 380.0) * 60.0 * (1.0 - rainStrength) * lmcoord.y;

        vec3 color = mix(waterCol, skyRef * 0.8, fresnel) + spec * sunColor(normalize(sunW), rainStrength);
        float alpha = clamp(mix(0.55, 0.95, fresnel) + (1.0 - trans.g) * 0.3, 0.0, 1.0);
        if (isEyeInWater == 1) { color = waterCol; alpha = 0.35; }

/* DRAWBUFFERS:015 */
        gl_FragData[0] = vec4(color, alpha);
        gl_FragData[1] = vec4(nV * 0.5 + 0.5, 0.7);
        gl_FragData[2] = vec4(lmcoord, 1.0, 1.0);
    } else {
        // Other translucents: stained glass, ice… (HDR-scaled, blends over lit scene)
        float light = lmcoord.y * lmcoord.y * 3.0 + lmcoord.x * lmcoord.x * 1.2 + 0.05;
/* DRAWBUFFERS:015 */
        gl_FragData[0] = vec4(albedo.rgb * light, albedo.a);
        gl_FragData[1] = vec4(normalV * 0.5 + 0.5, 0.5);
        gl_FragData[2] = vec4(lmcoord, 1.0, 1.0);
    }
}
