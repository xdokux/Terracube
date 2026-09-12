#version 120
// AETHER — shadow map with distortion for near-camera detail
#include "/lib/settings.glsl"

varying vec2 texcoord;
varying vec4 glcolor;

vec2 distortShadow(vec2 p) {
    float len = length(p);
    return p / (len * 0.85 + 0.15);
}

void main() {
    gl_Position = ftransform();
    gl_Position.xy = distortShadow(gl_Position.xy);
    gl_Position.z *= 0.5;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
}
