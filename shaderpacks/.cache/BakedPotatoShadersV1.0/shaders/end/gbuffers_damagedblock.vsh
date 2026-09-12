#version 120

#include "/lib/settings.glsl"

varying vec2 vTexCoord;
varying vec4 vColor;

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    gl_Position = (gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex);
}
