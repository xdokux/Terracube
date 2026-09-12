#version 120

/* composite1.vsh — quad a pantalla completa (bloom, paso horizontal). */

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
