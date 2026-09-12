#version 120

varying vec2 texcoord;
varying vec4 vcolor;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.st;
    vcolor = gl_Color;
}