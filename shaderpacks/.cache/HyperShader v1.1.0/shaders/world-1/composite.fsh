#version 120

/* composite.fsh (NETHER) — passthrough. El Nether se ve VANILLA (con la lava
   emisiva de gbuffers_terrain). Sin niebla ni cielo custom. */

uniform sampler2D colortex0;
varying vec2 texcoord;

/* DRAWBUFFERS:0 */
void main() {
    gl_FragData[0] = texture2D(colortex0, texcoord);
}
