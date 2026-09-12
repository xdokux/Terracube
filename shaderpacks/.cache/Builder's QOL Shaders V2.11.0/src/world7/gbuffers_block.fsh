#version 120

#include "lib/defines.glsl"

uniform float frameTimeCounter;
uniform int blockEntityId;
uniform sampler2D gaux1; //Overworld texture
uniform sampler2D gaux2; //End island texture
uniform sampler2D noisetex;
uniform sampler2D texture;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec3 vPosPlayer;
varying vec3 vPosView;
varying vec4 tint;

#ifdef END_PORTAL_EFFECTS_TF
	struct Position {
		vec3 view;
		vec3 player;
		vec3 playerNorm;
		float blockDist;
	};

	#include "/lib/noiseres.glsl"

	#include "/lib/goldenOffsets.glsl"

	#include "/lib/math.glsl"

	#include "/lib/hue.glsl"

	#if END_PORTAL_BACKGROUND_TF == 2
		#include "/lib/endEffects.glsl"
	#endif

	#if END_PORTAL_CLOUDS_TF == 1
		#ifdef OLD_CLOUDS
			#include "/lib/fastDrawClouds_old.glsl"
		#else
			#include "/lib/fastDrawClouds.glsl"
		#endif
	#elif END_PORTAL_CLOUDS_TF == 2
		#include "/lib/fastDrawVoidClouds.glsl"
	#endif
#endif

void main() {
	vec4 color = texture2D(texture, texcoord) * tint;

	#ifdef END_PORTAL_EFFECTS_TF
		if (blockEntityId == 119) {
			Position pos;
			pos.view = vPosView;
			pos.player = vPosPlayer;
			pos.blockDist = length(vPosView);
			pos.playerNorm = vPosPlayer / pos.blockDist;

			#include "/lib/endPortalEffects.glsl"
		}
	#endif

/* DRAWBUFFERS:04 */
	gl_FragData[0] = color; //gcolor
	gl_FragData[1] = vec4(lmcoord, 1.0, 1.0); //gaux1
}