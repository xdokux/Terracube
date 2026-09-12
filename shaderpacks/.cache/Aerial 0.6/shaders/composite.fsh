#version 120
// AETHER composite — water physics pass:
//   Snell refraction (distortion), caustics (light projection),
//   turbidity (noise fog inside the water column)
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;   // includes water surface
uniform sampler2D depthtex1;   // solid only
uniform vec3 cameraPosition;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform float frameTimeCounter;
uniform int isEyeInWater;

varying vec2 texcoord;

vec3 getViewPos(sampler2D depthTex, vec2 uv) {
    float d = texture2D(depthTex, uv).r;
    vec4 ndc = gbufferProjectionInverse * vec4(vec3(uv, d) * 2.0 - 1.0, 1.0);
    return ndc.xyz / ndc.w;
}

void main() {
    vec4 gdata = texture2D(colortex1, texcoord);
    float mat = gdata.a;
    vec3 color = texture2D(colortex0, texcoord).rgb;

    // Only water surface pixels, viewed from air
    if (mat > 0.65 && mat < 0.75 && isEyeInWater == 0) {
        vec3 normal = normalize(gdata.rgb * 2.0 - 1.0);
        vec3 vpWater = getViewPos(depthtex0, texcoord);
        vec3 vpSolid = getViewPos(depthtex1, texcoord);
        float waterDist = max(length(vpSolid) - length(vpWater), 0.0);

        // ---- Snell refraction: wave normal bends the sampled background ----
        float bend = clamp(waterDist * 0.5, 0.0, 1.0) * 0.018 / max(length(vpWater) * 0.08, 1.0);
        vec2 refUV = texcoord + normal.xy * bend;
        // Don't refract things in front of the water
        vec3 vpRef = getViewPos(depthtex1, refUV);
        if (length(vpRef) < length(vpWater) + 0.05) { refUV = texcoord; vpRef = vpSolid; }

        vec3 refColor = texture2D(colortex0, refUV).rgb;

        vec3 floorWorld = (gbufferModelViewInverse * vec4(vpRef, 1.0)).xyz + cameraPosition;

        #ifdef CAUSTICS_ENABLED
        // ---- caustics: sharpened interference pattern on the floor ----
        float t = frameTimeCounter;
        float c1 = noise3(vec3(floorWorld.xz * 0.9, t * 0.9));
        float c2 = noise3(vec3(floorWorld.xz * 1.7 + 13.7, t * 1.2));
        float caust = pow(clamp(1.0 - abs(c1 - c2) * 2.6, 0.0, 1.0), 3.0);
        // Strongest in shallow water, fades with depth; scaled by scene light
        float shallow = exp(-waterDist * 0.25);
        refColor *= 1.0 + caust * shallow * 1.4 * clamp(luminance(refColor) * 2.0, 0.0, 1.0);
        #endif

        // ---- turbidity: uneven suspended-particle fog in the column ----
        float turb = fbm(vec3(floorWorld.xz * 0.12, t * 0.05)) * 0.5 + 0.5;
        float scatterAmt = 1.0 - exp(-waterDist * (0.06 + turb * 0.10) * WATER_ABSORPTION);
        vec3 scatterTint = color * 1.2; // in-scattered light takes the water body color
        refColor = mix(refColor, scatterTint, scatterAmt);

        // Keep the surface's own reflections/spec on top
        color = mix(color, refColor, 0.5);
    }

/* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(color, 1.0);
}
