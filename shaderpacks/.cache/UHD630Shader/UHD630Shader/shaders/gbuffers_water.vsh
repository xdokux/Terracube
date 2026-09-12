#version 120

varying vec3 normal;
varying vec4 color;
varying vec2 texcoord;
varying vec4 worldPos;

uniform mat4 gbufferModelViewInverse;

void main() {
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    worldPos = gbufferModelViewInverse * viewPos;

    texcoord = gl_MultiTexCoord0.st;
    color = gl_Color;
    normal = gl_NormalMatrix * gl_Normal;
}
