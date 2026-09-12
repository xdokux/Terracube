#version 120

#include "/lib/settings.glsl"

varying vec4 vColor;

void main() {
    vColor = gl_Color;
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
}
