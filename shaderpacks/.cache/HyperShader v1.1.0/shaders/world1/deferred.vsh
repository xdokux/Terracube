#version 120

/* deferred.vsh (End) — quad a pantalla completa. */

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
