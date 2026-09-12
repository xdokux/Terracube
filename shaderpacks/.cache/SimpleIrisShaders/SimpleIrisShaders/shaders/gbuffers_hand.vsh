/*
    gbuffers_hand.vsh
    ---------------------------------------------------------------
    Pipeline stage: GBUFFERS_HAND (held item/block, first-person)
    ---------------------------------------------------------------
*/
#version 330 compatibility

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec4 vertexColor;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    vertexColor = gl_Color;
    gl_Position = ftransform();
}
