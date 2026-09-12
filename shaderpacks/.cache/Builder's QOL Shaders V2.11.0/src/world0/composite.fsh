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
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D composite;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux3;
uniform sampler2D gaux4; //lightmap
#define lightmap gaux4
uniform sampler2D gcolor;
uniform sampler2D gnormal;
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

varying vec2 texcoord;
varying vec3 shadowColor; //Color of shadows. Sky-colored, to simulate indirect lighting.
varying vec3 skyLightColor; //Color of sky light. Is usually white during the day, and very dark blue at night.
varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.

struct Position {
	bool isSky;
	vec3 view;
	vec3 viewNorm;
	vec3 player;
	vec3 world;
	float blockDist; //distance measured in blocks
	float viewDist; //blockDist / far
};

/*
because this has to be defined in the .fsh stage in order for optifine to recognize it:
uniform float centerDepthSmooth;

const float eyeBrightnessHalflife = 20.0;
const float wetnessHalflife = 250.0;
const float drynessHalflife = 60.0;
const float centerDepthHalflife   =  1.0; //Smaller number makes DOF update faster [0.0625 0.09375 0.125 0.1875 0.25 0.375 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0 12.0 16.0]

const int gcolorFormat = RGBA16;
const int compositeFormat = RGBA16;
const int gaux3Format = RGBA16;
const int gnormalFormat = RGB16;
*/

const float actualSeaLevel = SEA_LEVEL - 0.1111111111111111; //water source blocks are 8/9'ths of a block tall, so SEA_LEVEL - 1/9.

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "lib/calcMainLightColor.glsl"

#include "lib/calcFogAmount.glsl"

#include "lib/calcFogColor.glsl"

#include "lib/calcUnderwaterFogColor.glsl"

Position posFromDepthtex(sampler2D depthtex) {
	Position pos;
	float depth = texture2D(depthtex, texcoord).r;
	pos.isSky = depth == 1.0;
	vec3 screen = vec3(texcoord, depth);
	vec4 tmp = gbufferProjectionInverse * vec4(screen * 2.0 - 1.0, 1.0);
	pos.view = tmp.xyz / tmp.w;
	pos.player = mat3(gbufferModelViewInverse) * pos.view;
	pos.world = pos.player + actualCameraPosition;
	pos.blockDist = length(pos.view);
	pos.viewDist = pos.blockDist / far;
	pos.viewNorm = pos.view / pos.blockDist;
	return pos;
}

void main() {
	vec2 tc = texcoord;

	Position nearPos = posFromDepthtex(depthtex0);
	Position farPos = posFromDepthtex(depthtex1);

	vec3 color = texture2D(gcolor, tc).rgb;
	vec4 aux = texture2D(gaux1, tc);

	vec4 aux2 = texture2D(gaux2, tc);
	vec4 normal = texture2D(gnormal, tc);
	normal.xyz = normal.xyz * 2.0 - 1.0;
	bool water = int(aux2.b * 10.0 + 0.1) == 1; //only ID I'm actually checking for in this stage.
	bool inWater = isEyeInWater == 1; //quicker to type.

	float underwaterEyeBrightness = eyeBrightnessSmooth.y / 240.0;
	#ifdef BRIGHT_WATER
		underwaterEyeBrightness = underwaterEyeBrightness * 0.5 + 0.5;
	#endif

	if (!farPos.isSky) {
		float skylight = aux.g;
		float blocklight = aux.r;
		float heldlight = 0.0;

		#ifdef BRIGHT_WATER
			if      ( water && !inWater) skylight = mix(skylight, skylight * 0.5 + 0.5, aux2.g); //max(skylight, aux2.g * 0.5);
			else if (!water &&  inWater) skylight = skylight * 0.5 + 0.5;
		#endif

		color *= calcMainLightColor(blocklight, skylight, heldlight, farPos);

		vec2 lmcoord = aux.rg;

		#include "lib/crossprocess.glsl"

		#include "lib/desaturate.glsl"

		//!water && !inWater = white fog in stage 1
		//!water &&  inWater = blue fog
		// water && !inWater = blue fog in stage 1 then white fog in stage 2
		// water &&  inWater = white fog in stage 1 then blue fog in stage 2

		//if water xor  inwater then blue fog
		//if water ==   inwater then white fog (stage 1)
		//if water and  inwater then blue fog
		//if water and !inwater then white fog (stage 2)

		#ifdef UNDERWATER_FOG
			if      (water && !inWater) color = calcUnderwaterFogColor(color, farPos.blockDist - nearPos.blockDist, aux2.g * aux2.g);
			else if (!water && inWater) color = calcUnderwaterFogColor(color, farPos.blockDist, underwaterEyeBrightness);
		#endif

		#ifdef FOG_ENABLED_OVERWORLD
			if (water == inWater) {
				float fogDistance = (water ? farPos.blockDist - nearPos.blockDist : farPos.blockDist) / fogEnd;
				float actualEyeBrightness = eyeBrightness.y / 240.0;
				#ifdef BRIGHT_WATER
					if (inWater) actualEyeBrightness = actualEyeBrightness * 0.5 + 0.5;
				#endif
				color = mix(calcFogColor(farPos.viewNorm) * min(max(aux.g, actualEyeBrightness) * 2.0, 1.0), color, calcFogAmount(farPos, fogDistance));
			}
		#endif

		if (blindness > 0.0) color.rgb *= interpolateSmooth1(max(1.0 - farPos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);
	}
	else {
		if (nearPos.isSky) {
			#ifdef INFINITE_OCEANS
				if (actualCameraPosition.y > actualSeaLevel) {
					if (nearPos.player.y < 0.0) {
						aux2.g = 0.96875;
						aux2.b = 0.1; //water ID
						normal = vec4(0.0, 1.0, 0.0, 1.0);
						water = true;
					}
				}
				else if (inWater) {
					if (nearPos.player.y > 0.0) {
						aux2.g = 0.96875;
						aux2.b = 0.1; //water ID
						normal = vec4(0.0, -1.0, 0.0, 1.0);
						water = true;
					}
					#ifdef UNDERWATER_FOG
						else {
							color = calcUnderwaterFogColorInfinity(underwaterEyeBrightness);
						}
					#endif
				}
			#else
				#ifdef UNDERWATER_FOG
					if (inWater) {
						color = calcUnderwaterFogColorInfinity(underwaterEyeBrightness);
					}
				#endif
			#endif
		}
		if (water && !inWater) {
			color = calcUnderwaterFogColorInfinity(0.9384765625);
		}
		color *= 1.0 - blindness;
	}

/* DRAWBUFFERS:025 */
	gl_FragData[0] = vec4(color, texture2D(gaux3, texcoord).r); //gcolor, storing transparency data in alpha channel
	gl_FragData[1] = normal * 0.5 + 0.5; //gnormal
	gl_FragData[2] = aux2; //gaux2
}