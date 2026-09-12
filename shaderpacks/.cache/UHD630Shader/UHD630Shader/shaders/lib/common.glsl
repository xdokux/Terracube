#ifndef COMMON_GLSL
#define COMMON_GLSL

// Cheap dither pattern - avoids banding in godrays/SSR without a full blue-noise texture,
// which would mean an extra texture sample (extra bandwidth) on a weak iGPU.
float interleavedGradientNoise(vec2 uv) {
    const vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(uv, magic.xy)));
}

// Reconstructs a view-space position from a screen UV + depth sample.
// Requires gbufferProjectionInverse to be passed in from the calling shader.
vec3 reconstructViewPos(vec2 uv, float depth, mat4 projInverse) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewSpace = projInverse * clip;
    return viewSpace.xyz / viewSpace.w;
}

#endif
