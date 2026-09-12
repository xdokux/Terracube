#version 460 compatibility

attribute vec4 mc_Entity;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;

#include "/distort.glsl"

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;

	if(abs(mc_Entity.x - 10060.0) < 0.1)
	{
		// Exclude water
		gl_Position = vec4(10.0);
	} else {
		gl_Position = ftransform();
		//gl_Position.z += 0.1;
		gl_Position.xyz = distort(gl_Position.xyz);
	}
}