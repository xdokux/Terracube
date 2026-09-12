#version 120
/* DRAWBUFFERS:2 */
// Buffer 2 = godray mask only (R8 - single channel, cheapest possible buffer)

#include "/lib/common.glsl"

varying vec2 texcoord;

uniform sampler2D depthtex0;
uniform mat4 gbufferProjection;
uniform vec3 sunPosition; // already in view-space direction per Iris/OptiFine convention

// GODRAY_SAMPLES is swapped by shader.properties profiles (LOW/MEDIUM/HIGH).
#define GODRAY_SAMPLES 4 // [4 8 12 16] Godray sample count. Lower = faster, more banding.

const float godrayDensity  = 0.94;
const float godrayDecay    = 0.96;
const float godrayWeight   = 0.45;
const float godrayExposure = 0.35;

void main() {
    // Project the sun direction to screen space. sunPosition is a view-space
    // direction, not a world position, so we push it out along itself and
    // project with gbufferProjection only (no modelview needed - already applied).
    vec4 sunClip = gbufferProjection * vec4(sunPosition * 100.0, 1.0);

    if (sunClip.w <= 0.0) {
        // Sun is behind the camera - skip all sampling, cheap early exit.
        gl_FragData[0] = vec4(0.0);
        return;
    }

    vec2 sunScreenPos = (sunClip.xy / sunClip.w) * 0.5 + 0.5;

    vec2 deltaTexCoord = (texcoord - sunScreenPos) * (1.0 / float(GODRAY_SAMPLES)) * godrayDensity;

    // Dither the starting sample position to hide the low sample count as noise
    // instead of visible banding rings - much cheaper than adding more samples.
    float dither = interleavedGradientNoise(gl_FragCoord.xy);
    vec2 sampleCoord = texcoord - deltaTexCoord * dither;

    float illuminationDecay = 1.0;
    float accumulated = 0.0;

    for (int i = 0; i < GODRAY_SAMPLES; i++) {
        sampleCoord -= deltaTexCoord;
        float depthSample = texture2D(depthtex0, sampleCoord).r;
        float skyMask = step(0.9999, depthSample); // 1.0 = sky (far plane), 0.0 = terrain
        accumulated += skyMask * illuminationDecay * godrayWeight;
        illuminationDecay *= godrayDecay;
    }

    gl_FragData[0] = vec4(vec3(accumulated * godrayExposure), 1.0);
}
