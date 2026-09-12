#version 120

#include "lib/defines.glsl"

uniform float blindness;
uniform float centerDepthSmooth;
uniform float frameTimeCounter;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;

#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
	varying float dofDistance; //Un-projected centerDepthSmooth
#endif
varying float eyeAdjust;
varying vec2 texcoord;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif
#ifdef VOID_CLOUDS
	varying vec4 voidCloudInsideColor; //Color to render over your entire screen when inside a void cloud.
#endif

#include "/lib/noiseres.glsl"

#include "/lib/goldenOffsets.glsl"

#include "/lib/math.glsl"

#include "/lib/calcHeldLightColor.glsl"

#ifdef VOID_CLOUDS
	#include "/lib/hue.glsl"

	#include "lib/drawVoidClouds.glsl"
#endif

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif

	eyeAdjust = mix(EYE_ADJUST_END_DARK, EYE_ADJUST_END_LIGHT, eyeBrightnessSmooth.x / 240.0);

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		vec4 v = gbufferProjectionInverse * vec4(0.0, 0.0, centerDepthSmooth * 2.0 - 1.0, 1.0);
		dofDistance = -v.z / v.w;
	#endif

	#ifdef VOID_CLOUDS
		float d = abs(actualCameraPosition.y - VOID_CLOUD_HEIGHT) / 4.0;
		if (d < 1.0) {
			voidCloudInsideColor = drawVoidClouds(vec3(0.0, 1.0, 0.0), d);
			if (voidCloudInsideColor.a > 0.001) {
				if (d > 0.001 && d < 0.999) { //in the fadeout range
					voidCloudInsideColor.a *= interpolateSmooth1(d);
					voidCloudInsideColor *= 0.9; //why am I doing this again?
				}
			}
		}
		else voidCloudInsideColor = vec4(0.0);
	#endif
}