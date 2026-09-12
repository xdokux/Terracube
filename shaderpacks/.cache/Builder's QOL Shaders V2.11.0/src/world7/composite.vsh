#version 120

#include "lib/defines.glsl"

uniform float frameTimeCounter;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform sampler2D noisetex;

varying vec2 texcoord;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

#include "/lib/noiseres.glsl"

#include "/lib/calcHeldLightColor.glsl"

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	gl_Position = ftransform();

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif
}