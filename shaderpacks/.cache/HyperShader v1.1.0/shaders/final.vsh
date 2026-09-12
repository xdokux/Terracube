#version 120

/* final.vsh — Quad a pantalla completa para el pase final. */

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
