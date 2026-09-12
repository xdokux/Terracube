#version 120

#include "lib/defines.glsl"

uniform float blindness;
uniform float darknessLightFactor;
uniform float far;
uniform float fov;
uniform float frameTimeCounter;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform int isEyeInWater;
bool inWater = isEyeInWater == 1; //quicker to type
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
#define lightmap gaux4
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;

varying vec2 texcoord;
varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.

struct Position {
	bool isSky;
	vec3 view;
	vec3 viewNorm;
	vec3 player;
	vec3 playerNorm;
	vec3 world;
	float blockDist; //distance measured in blocks
	float viewDist; //blockDist / far
};

/*
because this has to be defined in the .fsh stage in order for optifine to recognize it:
uniform float centerDepthSmooth;

const float eyeBrightnessHalflife = 20.0;
const float centerDepthHalflife   =  1.0; //Smaller number makes DOF update faster [0.0625 0.09375 0.125 0.1875 0.25 0.375 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0 12.0 16.0]

const int gcolorFormat    = RGBA16;
const int compositeFormat = RGBA16;
const int gaux3Format     = RGBA16;
const int gnormalFormat   = RGB16;
*/

#include "/lib/noiseres.glsl"

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "lib/calcMainLightColor.glsl"

#include "lib/calcFogColor.glsl"

#include "lib/calcUnderwaterFogColor.glsl"

#include "/lib/hue.glsl"

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
	pos.playerNorm = pos.player / pos.blockDist;
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

	float skylight = aux.g;
	float blocklight = aux.r;
	float heldlight = 0.0;

	float underwaterEyeBrightness = eyeBrightnessSmooth.y / 240.0;
	#ifdef BRIGHT_WATER
		underwaterEyeBrightness = underwaterEyeBrightness * 0.5 + 0.5;
	#endif

	if (!farPos.isSky) {
		#ifdef BRIGHT_WATER
			if      ( water && !inWater) skylight = max(skylight, aux2.g * 0.5);
			else if (!water &&  inWater) skylight = skylight * 0.5 + 0.5;
		#endif

		color *= calcMainLightColor(blocklight, skylight, heldlight, farPos);

		vec2 lmcoord = aux.rg;

		#include "lib/crossprocess.glsl"

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

		#ifdef FOG_ENABLED_TF
			if (water == inWater) {
				float fogAmount = (water ? farPos.viewDist - nearPos.viewDist : farPos.viewDist) - 0.2;
				if (fogAmount > 0.0) {
					fogAmount = fogify(fogAmount * exp2(1.5 - farPos.world.y * 0.015625), FOG_DISTANCE_MULTIPLIER_TF);
					float actualEyeBrightness = eyeBrightness.y / 240.0;
					#ifdef BRIGHT_WATER
						if (inWater) actualEyeBrightness = actualEyeBrightness * 0.5 + 0.5;
					#endif
					color = mix(calcFogColor(farPos.viewNorm) * min(max(aux.g, actualEyeBrightness) * 2.0, 1.0), color, fogAmount);
				}
			}
		#endif

		if (blindness > 0.0) color.rgb *= interpolateSmooth1(max(1.0 - farPos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);
	}
	else {
		if (water && !inWater) {
			color = calcUnderwaterFogColorInfinity(aux2.g * aux2.g);
		}
		else if (!water && inWater) {
			color = calcUnderwaterFogColorInfinity(underwaterEyeBrightness);
		}
		#ifdef TF_SKY_FIX
			else color = calcFogColor(farPos.viewNorm);
		#endif

		#ifdef TF_AURORAS
			if (!water || inWater) {
				float auroraBrightness = 1.0 - abs(farPos.playerNorm.y - 0.5) * 3.0;
				if (farPos.playerNorm.y > 0.0 && auroraBrightness > 0.0) {
					vec2 auroraStart = farPos.playerNorm.xz / farPos.playerNorm.y * invNoiseRes;
					vec2 auroraStep = auroraStart * -0.5;
					float dither = fract(dot(gl_FragCoord.xy, vec2(0.25, 0.5))) * 0.0625;
					float time = frameTimeCounter * invNoiseRes;
					vec3 auroraColor = vec3(0.0);
					for (int i = 0; i < 16; i++) {
						vec2 auroraPos = (i * 0.0625 + dither) * auroraStep + auroraStart;
						float noise = 1.0 - abs(texture2D(noisetex, vec2(auroraPos.x * 0.5 + (time * 0.03125), auroraPos.y * 2.0)).r * 10.0 - 5.0); //primary noise layer, defines the overall shape of auroras
						if (noise > 0.0) {
							noise *= square(texture2D(noisetex, vec2(auroraPos.x * 16.0, auroraPos.y * 16.0 + (time * 0.5))).r * 2.0 - 1.0); //secondary noise layer, adds detail to the auroras
							auroraColor += hue(texture2D(noisetex, auroraPos * 3.0 + (time * 0.1875)).r * 0.5 + 0.35) * noise * square(1.0 - abs(float(i) * 0.125 - 1.0)); //tertiary noise layer, defines the color of the auroras
						}
					}
					color += sqrt(auroraColor) * 0.75 * interpolateSmooth1(auroraBrightness);
				}
			}
		#endif

		color *= 1.0 - blindness;
	}

/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(color, texture2D(gaux3, texcoord).r); //gcolor, storing transparency data in alpha channel
}