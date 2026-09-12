// final.fsh - composite.fsh already did the color work; this just presents
// colortex0 to the screen. Kept as a separate stage (rather than having
// composite target the screen directly) because every pack in the log that
// worked cleanly had an explicit final0 in its pass chain.

varying vec2 texcoord;

uniform sampler2D colortex0;

void main() {
	gl_FragData[0] = vec4(texture2D(colortex0, texcoord).rgb, 1.0);
}
