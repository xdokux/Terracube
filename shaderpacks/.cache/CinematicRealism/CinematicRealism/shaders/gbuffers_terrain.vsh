#version 330 compatibility

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;
varying float blockId;

attribute vec4 mc_Entity;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    vertexColor = gl_Color;
    blockId = mc_Entity.x;

    vec4 position = gl_ModelViewMatrix * gl_Vertex;
    viewPos = position.xyz;
    gl_Position = gl_ProjectionMatrix * position;
}
