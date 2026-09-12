#version 120

uniform sampler2D texture;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 tint;

void main() {
	vec4 color = texture2D(texture, texcoord) * tint;

/* DRAWBUFFERS:04 */
	gl_FragData[0] = color; //gcolor
	gl_FragData[1] = vec4(lmcoord, 1.0, color.a); //gaux1
}