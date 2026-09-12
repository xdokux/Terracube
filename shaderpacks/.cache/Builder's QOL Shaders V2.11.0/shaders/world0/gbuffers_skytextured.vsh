#version 120

varying vec2 texcoord;
varying vec4 tint;

void main() {
	gl_Position = ftransform();
	tint = gl_Color;
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}