#version 120

// GamesofDev is non chalant
varying vec3 viewPos;
varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
