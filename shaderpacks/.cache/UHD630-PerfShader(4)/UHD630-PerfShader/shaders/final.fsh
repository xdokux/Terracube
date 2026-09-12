#version 120

// Cheap color grading, aiming for a warmer, richer look closer to
// packs like Photon / Complementary Reimagined. This whole block is a
// few multiply-adds - negligible GPU cost.
#define WARMTH 0.12      // Warm white-balance strength [0.0 0.05 0.08 0.1 0.12 0.15 0.18 0.2 0.25]
#define SATURATION 1.18  // Saturation multiplier [0.9 1.0 1.05 1.1 1.15 1.18 1.2 1.25 1.3]
#define CONTRAST 0.22    // S-curve contrast strength [0.0 0.1 0.15 0.2 0.22 0.25 0.3]

uniform sampler2D colortex0;

varying vec2 texcoord;

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    color = clamp(color, 0.0, 1.0);

    // v1/v2 had no color grading at all here - just passed vanilla
    // colors through with a shadow multiplier, which is what actually
    // read as "flat/washed out" compared to packs with real grading.

    // ---- Warm white balance: push red up, pull blue down slightly ----
    color.r *= (1.0 + WARMTH);
    color.b *= (1.0 - WARMTH * 0.6);

    // ---- Saturation boost ----
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(luma), color, SATURATION);

    // ---- Gentle S-curve contrast (subtle, keeps shadow/highlight detail) ----
    color = mix(color, smoothstep(0.0, 1.0, color), CONTRAST);

    color = clamp(color, 0.0, 1.0);
    gl_FragColor = vec4(color, 1.0);
}
