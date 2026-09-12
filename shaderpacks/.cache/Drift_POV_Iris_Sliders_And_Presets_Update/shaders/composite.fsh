#version 120

// --- DRIFT POV PRO SETTINGS ---
#define BLUR_SAMPLES 16 // [4 8 12 16 24 32]
#define BLUR_STRENGTH 1.0 // [0.1 0.2 0.4 0.6 1.0 1.5 2.0 2.5 3.0]
#define ENABLE_NOISE // [true false]

varying vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

// Simple cinematic noise generator
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec4 color = texture2D(colortex0, texcoord);
    float depth = texture2D(depthtex0, texcoord).r;

    // Hand Protection
    if (depth < 0.56 || depth >= 1.0) {
        gl_FragData[0] = color;
        return;
    }

    // Matrix Reprojection
    vec4 currentPos = vec4(texcoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 fragPos = gbufferProjectionInverse * currentPos;
    fragPos = gbufferModelViewInverse * (fragPos / fragPos.w);

    vec4 prevPos = fragPos;
    prevPos.xyz += (cameraPosition - previousCameraPosition);
    prevPos = gbufferPreviousModelView * prevPos;
    prevPos = gbufferPreviousProjection * prevPos;
    prevPos /= prevPos.w;

    vec2 prevTexcoord = prevPos.xy * 0.5 + 0.5;

    // Velocity (Motion intensity is now independent of samples)
    vec2 velocity = (texcoord - prevTexcoord) * BLUR_STRENGTH;
    velocity = clamp(velocity, vec2(-0.05), vec2(0.15));

    // Blur Loop Setup
    vec4 blurResult = color;
    int samples = BLUR_SAMPLES;
    
    // Apply Cinematic Noise
    float dither = 0.5;
    #ifdef ENABLE_NOISE
    dither = hash(texcoord + cameraPosition.xy);
    #endif

    for (int i = 1; i < samples; ++i) {
        // Fix: This math now spreads the samples across the FULL length of the velocity
        float offsetMult = (float(i) - dither) / float(samples - 1) - 0.5;
        vec2 sampleCoord = clamp(texcoord + (velocity * offsetMult), 0.001, 0.999);
        blurResult += texture2D(colortex0, sampleCoord);
    }

    gl_FragData[0] = blurResult / float(samples);
}