#version 120

#include "lib/defines.glsl"

uniform float adjustedTime;
uniform float blindness;
uniform float darknessLightFactor;
uniform float day;
uniform float far;
uniform float fogEnd;
uniform float fov;
uniform float night;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float rainStrength;
uniform float screenBrightness;
uniform float sunset;
uniform float wetness;
uniform int isEyeInWater;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelViewInverse;
uniform sampler2D lightmap;
uniform sampler2D texture;
uniform vec3 actualCameraPosition;
#ifdef IS_IRIS
	uniform vec3 eyePosition;
#else
	vec3 eyePosition = actualCameraPosition;
#endif
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunPosNorm;
uniform vec3 upPosNorm;

varying float mcentity; //ID data of block currently being rendered.
varying vec2 lmcoord;
varying vec2 texcoord;
varying vec3 normal;
varying vec3 shadowColor; //Color of shadows. Sky-colored, to simulate indirect lighting.
varying vec3 skyLightColor; //Color of sky light. Is usually white during the day, and very dark blue at night.
varying vec3 vPosPlayer;
varying vec3 vPosView;
varying vec4 tint;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

struct Position {
	vec3 view;
	vec3 viewNorm;
	vec3 player;
	vec3 world;
	float blockDist;
	float viewDist;
};

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "lib/calcMainLightColor.glsl"

#include "lib/calcFogAmount.glsl"

#include "lib/calcFogColor.glsl"

void main() {
	int id = int(mcentity);
	vec4 color = texture2D(texture, texcoord) * tint;

	float skylight = lmcoord.y;
	float blocklight = lmcoord.x;
	float heldlight = 0.0;

	bool applyLighting = true;
	#ifdef FOG_ENABLED_OVERWORLD
		bool applyFog = true;
	#endif

	if (id == 1) {
		#ifdef CLEAR_WATER
			color.a = 0.0;
			applyLighting = false;
		#endif
		#ifdef FOG_ENABLED_OVERWORLD
			applyFog = false; //handled in composite
		#endif
	}
	else if (id == 2) {
		if (color.a > THRESHOLD_ALPHA) {
			color.a = 1.0; //make borders opaque
			id = 0;
		}
		#ifdef ALT_GLASS
			else {
				applyLighting = false;
				#ifdef FOG_ENABLED_OVERWORLD
					applyFog = false;
				#endif
			}
		#endif
	}

	Position pos;
	pos.view = vPosView;
	pos.player = vPosPlayer;
	pos.world = vPosPlayer + actualCameraPosition;
	pos.blockDist = length(pos.view);
	pos.viewDist = pos.blockDist / far;
	pos.viewNorm = pos.view / pos.blockDist;

	if (applyLighting) {
		#ifdef BRIGHT_WATER
			if (isEyeInWater == 1) skylight = skylight * 0.5 + 0.5;
		#endif

		color.rgb *= calcMainLightColor(blocklight, skylight, heldlight, pos);

		#include "lib/desaturate.glsl"

		#include "lib/crossprocess.glsl"

		if (blindness > 0.0) color.rgb *= interpolateSmooth1(max(1.0 - pos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);
	}

	#ifdef FOG_ENABLED_OVERWORLD
		if (applyFog) {
			color.rgb = mix(calcFogColor(pos.viewNorm) * min(max(lmcoord.y * 2.0, eyeBrightness.y / 120.0), 1.0) * (1.0 - blindness), color.rgb, calcFogAmount(pos, pos.blockDist / fogEnd));
		}
	#endif

/* DRAWBUFFERS:2563 */
	gl_FragData[0] = vec4(normal, 1.0); //gnormal, write to here first so that it won't discard other buffers when opacity is low
	gl_FragData[1] = vec4(lmcoord, id * 0.1, 1.0); //gaux2
	gl_FragData[2] = vec4(1.0, 0.0, 0.0, color.a); //gaux3
	gl_FragData[3] = color; //composite
}