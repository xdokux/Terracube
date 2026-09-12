#version 130

#include "distort.glsl"

out vec2 TexCoords;
out vec4 Color;

void main(){
    gl_Position = ftransform();
    gl_Position.xyz = DistortPosition(gl_Position.xyz);
    TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    Color = gl_Color;
}