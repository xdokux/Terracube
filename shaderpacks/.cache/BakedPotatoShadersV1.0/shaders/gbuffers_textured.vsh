#version 120

#include "/lib/settings.glsl"

uniform mat4 gbufferModelViewInverse;

varying vec2 vTexCoord;
varying vec4 vColor;
varying vec3 vPlayerPosition;

void main() {
    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vPlayerPosition = (gbufferModelViewInverse * viewPosition).xyz;
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
