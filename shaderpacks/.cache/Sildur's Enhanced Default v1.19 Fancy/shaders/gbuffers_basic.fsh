#version 120
/* DRAWBUFFERS:02 */ //0=gcolor, 2=gnormal for normals

uniform sampler2D lightmap;

varying vec2 lmcoord;
varying vec4 color;

void main() {
	gl_FragData[0] = color * texture2D(lightmap, lmcoord);
	gl_FragData[1] = vec4(0.0);
}