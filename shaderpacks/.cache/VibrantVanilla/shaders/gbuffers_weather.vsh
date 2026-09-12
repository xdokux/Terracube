#version 120
uniform mat4 shadowModelViewMatrix;
uniform mat4 shadowProjectionMatrix;
uniform mat4 gbufferModelViewInverse;
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec4 shadowcoord;
varying vec3 viewPos;
void main() {
    vec4 position = gl_Vertex;
    gl_Position = gl_ModelViewProjectionMatrix * position;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor = gl_Color;
    vec4 vPos = gl_ModelViewMatrix * position;
    viewPos = vPos.xyz;
    vec4 wPos = gbufferModelViewInverse * vPos;
    shadowcoord = shadowProjectionMatrix * shadowModelViewMatrix * wPos;
}
