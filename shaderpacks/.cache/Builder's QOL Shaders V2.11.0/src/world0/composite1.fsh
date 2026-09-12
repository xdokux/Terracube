#version 120

#include "lib/defines.glsl"

uniform bool isSpectator;
uniform float adjustedTime;
uniform float aspectRatio;
uniform float blindness;
uniform float darknessLightFactor;
uniform float day;
uniform float far;
uniform float fogEnd;
uniform float fov;
uniform float frameTimeCounter;
uniform float night;
uniform float nightVision;
uniform float phase;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float rainStrength;
uniform float screenBrightness;
uniform float sunset;
uniform float wetness;
uniform int bedrockLevel = 0;
uniform int heightLimit = 384;
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
uniform sampler2D gaux4;
#define lightmap gaux4
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D noisetex;
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
//required on older versions of optifine for its option-parsing logic.
#ifdef BLUR_ENABLED
#endif
*/

const float actualSeaLevel = SEA_LEVEL - 0.1111111111111111; //water source blocks are 8/9'ths of a block tall, so SEA_LEVEL - 1/9.

#include "/lib/noiseres.glsl"

#include "/lib/goldenOffsets.glsl"

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "/lib/heatRefraction.glsl"

#include "lib/calcMainLightColor.glsl"

#include "/lib/noiseLOD.glsl"

#include "lib/calcSkyColorBasic.glsl"

#include "lib/calcFogAmount.glsl"

#include "lib/calcFogColor.glsl"

#include "lib/calcUnderwaterFogColor.glsl"

#ifdef CLOUDS
	#ifdef OLD_CLOUDS
		#include "lib/drawClouds_old.glsl"
	#else
		#include "lib/drawClouds.glsl"
	#endif
#endif

Position posFromDepthtex(sampler2D depthtex) {
	Position pos;
	float depth = texture2D(depthtex, texcoord).r;
	pos.isSky = depth == 1.0;
	vec3 screen = vec3(texcoord, depth) * 2.0 - 1.0;
	vec4 tmp = gbufferProjectionInverse * vec4(screen, 1.0);
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
	#include "/lib/lavaOverlay.glsl"

	vec2 tc = texcoord;

	vec3 oldaux2 = texture2D(gaux2, texcoord).rgb;
	int id = int(oldaux2.b * 10.0 + 0.1);
	vec3 normal = texture2D(gnormal, texcoord).xyz * 2.0 - 1.0;

	Position nearPos = posFromDepthtex(depthtex0);
	Position farPos = posFromDepthtex(depthtex1);

	#ifdef REFLECT
		float reflective = 0.0;
	#endif

	#ifdef CLOUDS
		bool isTCOffset = false; //tracks weather or not cloud positions need to be re-calculated due to water/ice refractions
	#endif

	float blur = 0.0;

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		blur = interpolateSmooth1(min(abs(farPos.blockDist - dofDistance) / dofDistance, 1.0)) * DOF_STRENGTH;
	#endif

	#if defined(BLUR_ENABLED) && WATER_BLUR != 0
		float waterBlur = float(WATER_BLUR); //slightly more dynamic than other types of blur, as high fog density will decrease this value, and being near a reflection of the sun will increase it.
	#endif

	if (id == 1) { //water or infinite oceans
		#ifdef REFLECT
			reflective = 0.5;
		#endif

		#ifdef INFINITE_OCEANS
			if (nearPos.isSky) {
				float diff = actualSeaLevel - actualCameraPosition.y;
				nearPos.player = vec3(nearPos.playerNorm.xz * (diff / nearPos.playerNorm.y), diff).xzy;
				nearPos.world = nearPos.player + actualCameraPosition;
				nearPos.blockDist = length(nearPos.player);
				nearPos.viewDist = nearPos.blockDist / far;
				nearPos.isSky = false;
			}
		#endif

		#if defined(WATER_REFRACT) || (defined(WATER_NORMALS) && defined(REFLECT))
			vec3 newPos = nearPos.world;
			ivec2 swizzles;
			float multiplier = 1.0;
			if (abs(normal.y) > 0.1) { //top/bottom surface
				if (abs(normal.y) < 0.999) newPos.xz -= normalize(normal.xz) * (frameTimeCounter * 3.0);
				else multiplier = (oldaux2.g * (0.75 - night * 0.375) + 0.25) + (oldaux2.g * min(rainStrength, wetness) * 1.5);
				swizzles = ivec2(0, 2);
			}
			else {
				newPos.y += frameTimeCounter * 4.0;
				if (abs(normal.x) < 0.02) swizzles = ivec2(0, 1);
				else swizzles = ivec2(2, 1);
			}

			vec2 offset = waterNoiseLOD(vec2(newPos[swizzles[0]], newPos[swizzles[1]]), nearPos.blockDist) * (multiplier * 0.015625); //witchcraft.
			#ifdef WATER_NORMALS
				normal[swizzles[0]] += offset[0] * 4.0;
				normal[swizzles[1]] += offset[1] * 4.0;
				normal = normalize(normal);
			#endif

			#ifdef WATER_REFRACT
				vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio) / max(nearPos.blockDist * 0.0625, 1.0);
				vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
				if (dot(normal, newnormal) > 0.9) { //don't offset on the edges of water
					tc = newtc;

					#ifdef CLOUDS
						isTCOffset = true;
					#endif
				}
			#endif
		#endif
	}
	else if (id == 2) { //stained glass
		#ifdef REFLECT
			reflective = 0.25;
		#endif

		#if defined(BLUR_ENABLED) && GLASS_BLUR != 0
			blur = max(blur, float(GLASS_BLUR));
		#endif
	}
	else if (id == 3 || id == 4) { //ice and held ice
		#ifdef REFLECT
			reflective = 0.25;
		#endif

		#if defined(BLUR_ENABLED) && ICE_BLUR != 0
			blur = max(blur, float(ICE_BLUR));
		#endif

		#if defined(ICE_REFRACT) || (defined(ICE_NORMALS) && defined(REFLECT))
			vec3 offset;
			if (id == 3) {
				vec2 coord = (abs(normal.y) < 0.001 ? vec2(nearPos.world.x + nearPos.world.z, nearPos.world.y) : nearPos.world.xz);
				offset = iceNoiseLOD(coord * 256.0, nearPos.blockDist) * 0.0078125;
			}
			else {
				vec2 coord = gl_FragCoord.xy + 0.5;
				offset = iceNoise(coord * 0.5) * 0.0078125;
			}

			#ifdef ICE_REFRACT
				vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio);
				vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
				if (dot(normal, newnormal) > 0.9) { //don't offset on the edges of ice
					tc = newtc;

					#ifdef CLOUDS
						isTCOffset = true;
					#endif
				}
			#endif

			#ifdef ICE_NORMALS
				normal = normalize(normal + offset * 8.0);
			#endif
		#endif
	}

	vec3 aux2 = texture2D(gaux2, tc).rgb;
	if (abs(aux2.b - oldaux2.b) > 0.02) {
		tc = texcoord;
		aux2 = texture2D(gaux2, tc).rgb;

		#ifdef CLOUDS
			isTCOffset = false;
		#endif
	}

	vec4 c = texture2D(gcolor, tc);
	vec3 color = c.rgb;
	float transparentAlpha = c.a; //using gcolor to store composite's alpha
	vec4 transparent = texture2D(composite, tc); //transparency of closest object to the camera

	#if defined(BLUR_ENABLED) && UNDERWATER_BLUR != 0
		if (isEyeInWater == 1) blur = float(UNDERWATER_BLUR);
	#endif

	#ifdef CLOUDS
		float cloudDiff = (bedrockLevel + heightLimit) - actualCameraPosition.y;
		vec3 baseCloudPos = nearPos.playerNorm;
		float cloudDist;
		vec4 cloudclr = vec4(0.0);
		//don't render clouds below you if you're below them, and vise versa.
		bool cloudy = sign(cloudDiff) == sign(baseCloudPos.y);
		if (cloudy) {
			//calculate base cloud plane position
			baseCloudPos = vec3(baseCloudPos.xz * (cloudDiff / baseCloudPos.y), cloudDiff).xzy;
			cloudDist = lengthSquared3(baseCloudPos) * 0.999; //avoid z-fighting by making clouds a little bit closer
			float opacityModifier = -1.0;
			//additional logic if there's terrain in front of the clouds (used for fake volumetric effects)
			if (!nearPos.isSky && nearPos.blockDist * nearPos.blockDist < cloudDist) {
				opacityModifier = abs(nearPos.world.y - (bedrockLevel + heightLimit)) * (1.0 / 16.0);
				if (opacityModifier < 1.0) { //maximum cloud density
					baseCloudPos = nearPos.player;
					cloudDist = nearPos.blockDist * 0.999;
				}
				else { //pos is outside range of fake volumetric effects, check farPos next.
					opacityModifier = -1.0;
					if (!farPos.isSky) { //opaque object exists here
						opacityModifier = abs(farPos.world.y - (bedrockLevel + heightLimit)) * (1.0 / 16.0);
						if (opacityModifier < 1.0 && farPos.blockDist < cloudDist) { //within volumetric range
							baseCloudPos = farPos.player;
							cloudDist = farPos.blockDist * 0.999;
						}
						else opacityModifier = -1.0;
						cloudy = farPos.blockDist > cloudDist; //true if there's clouds between the terrain and the transparent thing
					} //opaque object exists here too
				} //pos is outside range of fake volumetric effects, check farPos next.
			} //something in front of terrain

			if (cloudy) {
				if (isTCOffset && nearPos.blockDist * nearPos.blockDist < cloudDist) { //re-calculate position to account for water refraction.
					baseCloudPos = normalize((gbufferModelViewInverse * (gbufferProjectionInverse * vec4(tc * 2.0 - 1.0, 1.0, 1.0))).xyz);
					baseCloudPos = vec3(baseCloudPos.xz / baseCloudPos.y * cloudDiff, cloudDiff).xzy;
					//not re-calculating distance because it's not really all that necessary.
				}
				cloudDist = sqrt(cloudDist);
				cloudclr = drawClouds(baseCloudPos, nearPos.viewNorm, opacityModifier, false);

				cloudclr.a *= 64.0 / (lengthSquared2(baseCloudPos.xz / baseCloudPos.y) + 64.0); //reduce opacity in the distance

				if (cloudclr.a > 0.001) {
					if (opacityModifier > 0.0 && opacityModifier < 1.0) { //in the fadeout range
						cloudclr.a *= interpolateSmooth1(opacityModifier);
					}
				}
				else cloudy = false; //no need to render clouds that don't exist at this location
			}
		}
	#endif

	if (transparentAlpha > 0.001) {
		#ifdef CLOUDS
			if (cloudy && nearPos.blockDist < cloudDist) color = mix(color, cloudclr.rgb, cloudclr.a);
		#endif

		#ifdef ALT_GLASS
			if (id == 2) {
				vec3 transColor = transparent.rgb / transparentAlpha;
				color *= transColor * (2.0 - transColor); //because the default colors are too dark to be used.

				float skylight = aux2.g;
				float blocklight = aux2.r;
				float heldlight = 0.0;

				color += transColor * calcMainLightColor(blocklight, skylight, heldlight, nearPos) * 0.125 * (1.0 - blindness);
			}
			else
		#endif
				color = mix(color, transparent.rgb / transparentAlpha, transparentAlpha);
	}
	#ifdef CLOUDS
		else if (cloudy && (/* dist < cloudDist || */ id != 1 || isEyeInWater == 1)) color = mix(color, cloudclr.rgb, cloudclr.a);
	#endif

	#ifdef REFLECT
		reflective *= aux2.g * aux2.g * (1.0 - blindness);
		vec3 reflectedPos;
		if (isEyeInWater == 0 && reflective > 0.001) { //sky reflections
			vec3 newnormal = mat3(gbufferModelView) * normal;
			reflectedPos = reflect(nearPos.viewNorm, newnormal);
			vec3 skyclr = calcSkyColor(reflectedPos);
			float posDot = dot(-nearPos.viewNorm, newnormal);
			color += skyclr * square(square(1.0 - max(posDot, 0.0))) * reflective;
		}
	#endif

	if (id > 0) { //everything that I've currently assigned effects to so far needs fog to be done in this stage.
		if (isEyeInWater == 1) {
			#ifdef UNDERWATER_FOG
				float actualEyeBrightness = eyeBrightnessSmooth.y / 240.0;
				#ifdef BRIGHT_WATER
					actualEyeBrightness = actualEyeBrightness * 0.5 + 0.5;
				#endif
				color = calcUnderwaterFogColor(color, nearPos.blockDist, actualEyeBrightness) * (1.0 - blindness);
			#endif
		}
		else {
			#ifdef FOG_ENABLED_OVERWORLD
				vec3 fogclr = calcFogColor(nearPos.viewNorm);
				fogclr += fract(dot(gl_FragCoord.xy, vec2(0.25, 0.5))) * 0.00390625; //dither to match sky
				float fogAmount = calcFogAmount(nearPos, nearPos.blockDist / fogEnd);
				color = mix(fogclr * min(max(aux2.g * 2.0, eyeBrightness.y / 120.0), 1.0) * (1.0 - blindness), color, fogAmount);
				#if defined(BLUR_ENABLED) && WATER_BLUR != 0
					waterBlur *= fogAmount;
				#endif
			#endif
		}
	}

	//sun reflections bypasses fog.
	#ifdef REFLECT
		reflective *= day * (1.0 - rainStrength);
		if (isEyeInWater == 0 && reflective > 0.001) {
			vec3 sunColor = mix(sunReflectionColorAtSunset, sunReflectionColorDuringTheDay, day);
			float sunDot = dot(reflectedPos, sunPosNorm);
			float reflectionAmount = sunReflectionBrightness / (sunReflectionInverseBrightness - sunDot);

			color = mix(vec3(1.0), color, exp2(-sunColor * reflectionAmount * reflective));

			#if defined(BLUR_ENABLED) && WATER_BLUR != 0
				waterBlur = clamp((sunDot - 0.75) * 16.0, waterBlur, WATER_BLUR); //no more than WATER_BLUR, and no less than what it was originally.
			#endif
		}
	#endif

	//color = min(color, 1.0); //reflections (and possibly other things) can go above maximum brightness

	#ifdef CLOUDS
		if (cloudy && (id == 1 || transparentAlpha > 0.001) && nearPos.blockDist > cloudDist) color = mix(color, cloudclr.rgb, cloudclr.a);
		color = mix(color, cloudInsideColor.rgb, cloudInsideColor.a);
	#endif

	#if defined(BLUR_ENABLED) && RAIN_BLUR != 0
		if (wetness > 0.001) {
			float skylight = texture2D(gaux1, tc).g;

			float heightModifier = 1.0;

			#ifdef CLOUDS
				heightModifier = fogify(max(actualCameraPosition.y - (bedrockLevel + heightLimit), 0.0), 6.25); //less rain blur above cloud height
			#endif

			blur += wetness * heightModifier * float(RAIN_BLUR) * (farPos.isSky ? 0.5 : max(eyeBrightnessSmooth.y / 120.0, skylight * 2.0) * nearPos.viewDist);
		}
	#endif

	#if defined(BLUR_ENABLED) && WATER_BLUR != 0
		if (id == 1 && isEyeInWater == 0) blur += waterBlur;
	#endif

	#ifdef BLUR_ENABLED
		blur /= 256.0;
	#endif

	color *= mix(vec3(eyeAdjust), vec3(1.0), color);

/* DRAWBUFFERS:6 */
	gl_FragData[0] = vec4(color, 1.0 - blur); //gaux3
}