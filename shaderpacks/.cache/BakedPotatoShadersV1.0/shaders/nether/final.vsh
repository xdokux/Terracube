#version 120

#include "/lib/settings.glsl"

varying vec2 vTexCoord;

void main() {
    vTexCoord = gl_MultiTexCoord0.xy;
    gl_Position = (gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex);
}
