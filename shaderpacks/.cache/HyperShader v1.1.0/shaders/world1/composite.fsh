#version 120

/* composite.fsh (END) — passthrough. El cielo del End ahora se dibuja en
   deferred (antes del cristal). Aquí solo anulamos la niebla/SSR del overworld
   para que no se apliquen en el End. */

uniform sampler2D colortex0;
varying vec2 texcoord;

/* DRAWBUFFERS:0 */
void main() {
    gl_FragData[0] = texture2D(colortex0, texcoord);
}
