#version 120

#include "/lib/distort.glsl"

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
    gl_Position.xyz = distort(gl_Position.xyz);
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor  = gl_Color;
}