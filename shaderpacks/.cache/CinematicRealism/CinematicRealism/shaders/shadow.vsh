/*
    shadow.vsh - depth-only shadow map render, with distortion applied
    so texel density is higher near the camera (the pseudo-cascade
    technique - see lib/shadows.glsl for the full explanation). This
    distortion MUST match distortShadowUV() exactly or shadows will
    be misaligned with the geometry that samples them.
*/
#version 330 compatibility

#include "lib/settings.glsl"

vec2 distortShadowClip(vec2 clipXY) {
    float distortFactor = length(clipXY) * SHADOW_DISTORTION + (1.0 - SHADOW_DISTORTION);
    return clipXY / distortFactor;
}

void main() {
    vec4 pos = ftransform();
    pos.xy = distortShadowClip(pos.xy);
    gl_Position = pos;
}
