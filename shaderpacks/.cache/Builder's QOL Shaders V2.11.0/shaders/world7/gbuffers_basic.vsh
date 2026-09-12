#version 120

varying vec2 lmcoord;
varying vec3 tint;

void main() {
	lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	gl_Position = ftransform();
	tint = gl_Color.rgb;
}