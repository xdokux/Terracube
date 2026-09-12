#version 120

#include "lib/defines.glsl"

uniform float centerDepthSmooth;
uniform float frameTimeCounter;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D noisetex;

#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
	varying float dofDistance; //Un-projected centerDepthSmooth
#endif
varying float eyeAdjust;
varying vec2 texcoord;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

#include "/lib/noiseres.glsl"

#include "/lib/calcHeldLightColor.glsl"

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	gl_Position = ftransform();

	float eyeBlocklight = eyeBrightnessSmooth.x / 240.0;
	float eyeSkylight = eyeBrightnessSmooth.y / 240.0;
	#ifdef BRIGHT_WATER
		if (isEyeInWater == 1) eyeSkylight = eyeSkylight * 0.5 + 0.5;
	#endif
	eyeAdjust = mix(EYE_ADJUST_TF_DARK, EYE_ADJUST_TF_LIGHT, max(eyeBlocklight, eyeSkylight));

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		vec4 v = gbufferProjectionInverse * vec4(0.0, 0.0, centerDepthSmooth * 2.0 - 1.0, 1.0);
		dofDistance = -v.z / v.w;
	#endif

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif
}