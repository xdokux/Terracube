#version 120

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vertexColor;
varying vec3 normal;
varying vec3 viewPos;

uniform vec3 cameraPosition;
uniform float frameTimeCounter;

void main() {
    vec3 feetPlayerPos = gl_Vertex.xyz;
    vec3 worldPos = feetPlayerPos + cameraPosition;

    float wave = sin(worldPos.x * 0.6 + frameTimeCounter * 1.6) * 0.02
               + sin(worldPos.z * 0.9 - frameTimeCounter * 1.1) * 0.015;
    feetPlayerPos.y += wave;

    vec4 vPos = gl_ModelViewMatrix * vec4(feetPlayerPos, 1.0);
    gl_Position = gl_ProjectionMatrix * vPos;
    viewPos = vPos.xyz;

    texcoord    = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord     = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vertexColor = gl_Color;
    normal      = gl_NormalMatrix * gl_Normal;
}
