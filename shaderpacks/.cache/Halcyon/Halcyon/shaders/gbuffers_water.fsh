#version 120

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform sampler2D colortex0;   // scene already lit by deferred.fsh
uniform sampler2D depthtex1;   // opaque-only depth (water itself is excluded)

uniform mat4 gbufferProjection;

uniform vec3 shadowLightPosition;
uniform vec3 upPosition;
uniform float rainStrength;
uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vertexColor;
varying vec3 normal;
varying vec3 viewPos;

const int SSR_STEPS = 20;
const float SSR_STEP_SIZE = 0.6;

// Simplified single-pass screen-space reflection: march along the reflected
// view-space ray, project each step to screen space, and test against the
// opaque depth buffer. First step that's behind existing geometry = a hit.
vec3 screenSpaceReflection(vec3 startPos, vec3 dir, out bool hit) {
    hit = false;
    vec3 rayPos = startPos;

    for (int i = 0; i < SSR_STEPS; i++) {
        rayPos += dir * SSR_STEP_SIZE;

        vec4 clip = gbufferProjection * vec4(rayPos, 1.0);
        if (clip.w <= 0.0) break;
        vec2 screenPos = (clip.xy / clip.w) * 0.5 + 0.5;

        if (screenPos.x < 0.0 || screenPos.x > 1.0 || screenPos.y < 0.0 || screenPos.y > 1.0) break;

        float sceneDepthNDC = texture2D(depthtex1, screenPos).r * 2.0 - 1.0;
        float rayDepthNDC = (clip.z / clip.w);

        if (rayDepthNDC > sceneDepthNDC) {
            hit = true;
            return texture2D(colortex0, screenPos).rgb;
        }
    }
    return vec3(0.0);
}

void main() {
    vec4 albedo = texture2D(texture, texcoord) * vertexColor;

    vec3 n = normalize(normal);
    vec3 viewDir = normalize(viewPos);
    vec3 lightDir = normalize(shadowLightPosition);

    float NdotL = max(dot(n, lightDir), 0.0);
    vec3 halfVec = normalize(lightDir - viewDir);
    float spec = pow(max(dot(n, halfVec), 0.0), 200.0) * (1.0 - rainStrength * 0.7);

    vec3 skyLight = texture2D(lightmap, lmcoord).rgb;
    vec3 directLight = vec3(1.0, 0.95, 0.85) * NdotL;

    // --- refraction: sample the already-lit scene behind the water with a small offset ---
    vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec2 refractOffset = n.xy * 0.03;
    vec3 refracted = texture2D(colortex0, clamp(screenUV + refractOffset, 0.0, 1.0)).rgb;

    // --- reflection ---
    vec3 reflectDir = reflect(viewDir, n);
    bool hit;
    vec3 reflection = screenSpaceReflection(viewPos, reflectDir, hit);
    if (!hit) {
        // Crude fallback sky approximation - not synced to the real procedural sky,
        // just enough to avoid a hard black reflection when SSR misses. See README.
        float skyFactor = clamp(dot(reflectDir, normalize(upPosition)) * 0.5 + 0.5, 0.0, 1.0);
        reflection = mix(vec3(0.5, 0.6, 0.75), vec3(0.3, 0.45, 0.8), skyFactor);
    }

    float fresnel = pow(1.0 - max(dot(n, -viewDir), 0.0), 5.0);
    fresnel = mix(0.05, 1.0, fresnel);

    vec3 waterColor = mix(refracted * albedo.rgb * (skyLight * 0.6 + directLight * 0.4),
                           reflection, fresnel);
    waterColor += spec * vec3(1.0, 0.98, 0.9);

    gl_FragColor = vec4(waterColor, max(albedo.a, fresnel * 0.6));
}
