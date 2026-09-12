#version 120

// GamesofDev is non chalant
varying vec2 texcoord;
varying vec4 glColor;
varying vec3 worldPos;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glColor = gl_Color;
    worldPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
}
