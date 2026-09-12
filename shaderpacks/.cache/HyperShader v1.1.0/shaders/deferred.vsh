#version 120

/* deferred.vsh — Quad a pantalla completa para dibujar el cielo. */

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
