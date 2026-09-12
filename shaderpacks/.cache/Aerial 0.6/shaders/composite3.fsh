#version 120
// AETHER composite3 — auto-exposure: measure scene, blend into history
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex4;   // persistent exposure history
uniform float frameTime;

varying vec2 texcoord;

void main() {
    // Center-weighted log-average luminance from a sparse grid
    float logSum = 0.0;
    float wsum = 0.0;
    for (int x = 0; x < 6; x++)
    for (int y = 0; y < 6; y++) {
        vec2 uv = (vec2(x, y) + 0.5) / 6.0;
        float w = 1.0 - length(uv - 0.5) * 0.9; // center weight
        float lum = luminance(texture2D(colortex0, uv).rgb);
        logSum += log(max(lum, 1e-4)) * w;
        wsum += w;
    }
    float avgLum = exp(logSum / wsum);

    // Target key with photographic clamp
    // Max clamped low: cranking exposure in caves blew out torch-lit
    // subjects (players, block entities) to pure white
    float targetExposure = clamp(0.33 / max(avgLum, 1e-4), 0.08, 2.6);
    targetExposure *= exp2(EXPOSURE_BIAS);

    #ifndef AUTO_EXPOSURE
    targetExposure = 1.0 * exp2(EXPOSURE_BIAS);
    #endif

    // Eye adaptation: fast to brighten reaction, slow to darken
    float prev = texture2D(colortex4, vec2(0.5)).r;
    if (prev <= 0.0) prev = targetExposure;
    float speed = targetExposure > prev ? 1.4 : 0.9;
    float exposure = mix(prev, targetExposure, clamp(frameTime * speed, 0.0, 1.0));

/* DRAWBUFFERS:4 */
    gl_FragData[0] = vec4(exposure, targetExposure, avgLum, 1.0);
}
