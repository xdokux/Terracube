#version 120

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

varying vec2 texcoord;
varying vec4 vColor;

void main() {
    gl_Position = shadowProjection * shadowModelView * gl_Vertex;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
}
