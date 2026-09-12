#version 120

/* composite2.vsh — quad a pantalla completa (bloom, paso vertical). */

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
