#version 120

#include "lib/defines.glsl"

uniform float adjustedTime;
uniform float day;
uniform float frameTimeCounter;
uniform float phase;
uniform float rainStrength;
uniform float sunset;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform ivec2 eyeBrightnessSmooth; //0-240
uniform sampler2D noisetex;
uniform vec3 fogColor;
uniform vec3 skyColor;

varying vec2 texcoord;
varying vec3 shadowColor; //Color of shadows. Sky-colored, to simulate indirect lighting.
varying vec3 skyLightColor; //Color of sky light. Is usually white during the day, and very dark blue at night.
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

#include "/lib/noiseres.glsl"

#include "lib/magicNumbers.glsl"

#include "/lib/calcHeldLightColor.glsl"

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif

	#include "lib/colors.glsl"
}