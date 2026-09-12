#version 120

/* deferred.fsh (NETHER) — Passthrough: solo existe para ANULAR el deferred
   base (que dibuja el cielo azul del overworld). La niebla del Nether se hace
   en composite.fsh (que lee la profundidad de forma fiable). */

uniform sampler2D colortex0;
varying vec2 texcoord;

/* DRAWBUFFERS:0 */
void main() {
    gl_FragData[0] = texture2D(colortex0, texcoord);
}
