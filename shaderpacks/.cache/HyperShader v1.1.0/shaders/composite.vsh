#version 120

/* composite.vsh — Pase a pantalla completa (quad). Solo pasa la UV. */

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
