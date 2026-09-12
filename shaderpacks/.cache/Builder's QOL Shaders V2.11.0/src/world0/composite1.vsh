#version 120

#include "lib/defines.glsl"

uniform float adjustedTime;
uniform float blindness;
uniform float centerDepthSmooth;
uniform float day;
uniform float frameTimeCounter;
uniform float night;
uniform float phase;
uniform float rainStrength;
uniform float sunset;
uniform float wetness;
uniform int bedrockLevel = 0;
uniform int heightLimit = 384;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform int isEyeInWater;
uniform int worldDay;
uniform int worldTime;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunPosNorm;
uniform vec4 lightningBoltPosition;

#ifdef CLOUDS
	varying float cloudDensityModifier; //Random fluctuations every few minutes.
#endif
#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
	varying float dofDistance; //Un-projected centerDepthSmooth
#endif
varying float eyeAdjust; //How much brighter to make the world
varying vec2 texcoord;
#ifdef CLOUDS
	varying vec3 cloudColor; //Color of the side of clouds facing away from the sun.
	varying vec3 cloudIlluminationColor; //Color of the side of clouds facing towards the sun.
#endif
varying vec3 shadowColor; //Color of shadows. Sky-colored, to simulate indirect lighting.
varying vec3 skyLightColor; //Color of sky light. Is usually white during the day, and very dark blue at night.
#ifdef CLOUDS
	varying vec4 cloudInsideColor; //Color to render over your entire screen when inside a cloud.
#endif
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

#include "/lib/noiseres.glsl"

#include "/lib/goldenOffsets.glsl"

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "/lib/calcHeldLightColor.glsl"

#ifdef CLOUDS
	#ifdef OLD_CLOUDS
		#include "lib/drawClouds_old.glsl"
	#else
		#include "lib/drawClouds.glsl"
	#endif
#endif

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	float eyeBlocklight = eyeBrightnessSmooth.x / 240.0;
	float eyeSkylight = eyeBrightnessSmooth.y / 240.0;
	#ifdef BRIGHT_WATER
		if (isEyeInWater == 1) eyeSkylight = eyeSkylight * 0.5 + 0.5;
	#endif
	eyeSkylight *= 1.0 - night;
	eyeAdjust = mix(EYE_ADJUST_OVERWORLD_DARK, EYE_ADJUST_OVERWORLD_LIGHT, max(eyeBlocklight, eyeSkylight));

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		vec4 v = gbufferProjectionInverse * vec4(0.0, 0.0, centerDepthSmooth * 2.0 - 1.0, 1.0);
		dofDistance = -v.z / v.w;
	#endif

	#ifdef CLOUDS
		if (wetness < 0.999) {
			//avoid some floating point precision errors on old worlds by modulus-ing the world day.
			//normally I'd just do the modulo on ints instead of floats, but if I've learned anything about GLSL, it's that it really doesn't like ints.
			//as such, I'll cast worldDay to a float instead in hopes that it won't randomly break on someone else's GPU.
			float randTime = (mod(float(worldDay), float(noiseTextureResolution)) + worldTime / 24000.0) * 5.0;
			randTime = floor(randTime) + interpolateSmooth1(fract(randTime)) + 0.5;
			cloudDensityModifier = ((texture2D(noisetex, vec2(randTime, 0.5) * invNoiseRes).r * 2.0 - 1.0) * CLOUD_DENSITY_VARIANCE + CLOUD_DENSITY_AVERAGE) * (1.0 - wetness);
			//float r0 = texelFetch2D(noisetex, ivec2(int(randTime)     % noiseTextureResolution, 0), 0).r;
			//float r1 = texelFetch2D(noisetex, ivec2(int(randTime + 1) % noiseTextureResolution, 0), 0).r;
			//cloudDensityModifier = (mix(r0, r1, interpolateSmooth1(fract(randTime))) * 3.0 - 1.5) * (1.0 - wetness);
		}
		else {
			cloudDensityModifier = 0.0;
		}

		cloudColor             = mix(cloudBaseColorDuringSunnyDays * day, fogColor * 0.5, wetness);
		cloudIlluminationColor = mix(cloudIlluminationColorWhenSunny, cloudIlluminationColorWhenRaining, wetness) * day;

		if (sunset > 0.001) {
			vec3 sunsetColor = clamp(sunsetColorForOtherThings - adjustedTime, 0.0, 1.0);
			cloudIlluminationColor = mix(cloudIlluminationColor, sunsetColor, sunset * (1.0 - wetness * 0.5));
		}

		float d = abs(actualCameraPosition.y - (bedrockLevel + heightLimit)) * (1.0 / 16.0);
		if (d < 1.0) {
			cloudInsideColor = drawClouds(vec3(0.0), vec3(0.0), d, true);
			if (cloudInsideColor.a > 0.0) {
				if (d > 0.0 && d < 1.0) cloudInsideColor.a *= interpolateSmooth1(d); //in the fadeout range
			}
		}
		else {
			cloudInsideColor = vec4(0.0);
		}
	#endif

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif

	#include "lib/colors.glsl"
}