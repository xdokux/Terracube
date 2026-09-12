#version 120

#include "lib/defines.glsl"

uniform bool isSpectator;
uniform float aspectRatio;
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
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D composite;
uniform sampler2D depthtex0;
uniform sampler2D gaux2;
uniform sampler2D gaux4;
#define lightmap gaux4
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;

#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
	varying float dofDistance; //Un-projected centerDepthSmooth
#endif
varying float eyeAdjust; //How much brighter to make the world
varying vec2 texcoord;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

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

#include "/lib/noiseres.glsl"

#include "/lib/goldenOffsets.glsl"

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "/lib/heatRefraction.glsl"

#include "lib/calcMainLightColor.glsl"

#include "/lib/noiseLOD.glsl"

#include "lib/calcFogColor.glsl"

#include "lib/calcUnderwaterFogColor.glsl"

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

	vec3 oldAux2 = texture2D(gaux2, texcoord).rgb;
	int id = int(oldAux2.b * 10.0 + 0.1);
	vec3 normal = texture2D(gnormal, texcoord).xyz * 2.0 - 1.0;

	Position nearPos = posFromDepthtex(depthtex0);

	#ifdef REFLECT
		float reflective = 0.0;
	#endif

	float blur = 0.0;

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		blur = interpolateSmooth1(min(abs(nearPos.blockDist - dofDistance) / dofDistance, 1.0)) * float(DOF_STRENGTH);
	#endif

	#if defined(BLUR_ENABLED) && WATER_BLUR != 0
		float waterBlur = float(WATER_BLUR); //slightly more dynamic than other types of blur
	#endif

	if (id == 1) { //water
		#ifdef REFLECT
			reflective = 0.5;
		#endif

		#if defined(WATER_REFRACT) || (defined(WATER_NORMALS) && defined(REFLECT))
			vec3 newPos = nearPos.world;
			ivec2 swizzles;
			float multiplier = 1.0;
			if (abs(normal.y) > 0.1) { //top/bottom surfaces
				if (abs(normal.y) < 0.999) newPos.xz -= normalize(normal.xz) * (frameTimeCounter * 3.0);
				else multiplier = oldAux2.g * 0.75 + 0.25;
				swizzles = ivec2(0, 2);
			}
			else {
				newPos.y += frameTimeCounter * 4.0;
				if (abs(normal.x) < 0.02) swizzles = ivec2(0, 1);
				else swizzles = ivec2(2, 1);
			}

			vec2 offset = waterNoiseLOD(vec2(newPos[swizzles[0]], newPos[swizzles[1]]), nearPos.blockDist) * (multiplier * 0.015625);
			#ifdef WATER_NORMALS
				normal[swizzles[0]] += offset[0] * 4.0;
				normal[swizzles[1]] += offset[1] * 4.0;
			#endif

			#ifdef WATER_REFRACT
				vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio) / max(nearPos.blockDist * 0.0625, 1.0);
				vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
				if (dot(normal, newnormal) > 0.9) { //don't offset on the edges of water
					tc = newtc;
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
			if (id == 3) { //normal ice
				vec2 coord = (abs(normal.y) < 0.001 ? vec2(nearPos.world.x + nearPos.world.z, nearPos.world.y) : nearPos.world.xz);
				offset = iceNoiseLOD(coord * 256.0, nearPos.blockDist) * 0.0078125;
			}
			else { //held ice
				vec2 coord = gl_FragCoord.xy + 0.5;
				offset = iceNoise(coord * 0.5) * 0.0078125;
			}

			#ifdef ICE_REFRACT
				vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio);
				vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
				if (dot(normal, newnormal) > 0.9) tc = newtc; //don't offset on the edges of ice
			#endif

			#ifdef ICE_NORMALS
				normal = normalize(normal + offset * 8.0);
			#endif
		#endif
	}

	vec3 aux2 = texture2D(gaux2, tc).rgb;
	if (abs(aux2.b - oldAux2.b) > 0.02) {
		tc = texcoord;
		aux2 = texture2D(gaux2, tc).rgb;
	}

	vec4 c = texture2D(gcolor, tc);
	vec3 color = c.rgb;
	float transparentAlpha = c.a; //using gcolor to store composite's alpha
	vec4 transparent = texture2D(composite, tc); //transparency of closest object to the camera

	#if defined(BLUR_ENABLED) && UNDERWATER_BLUR != 0
		if (isEyeInWater == 1) blur = float(UNDERWATER_BLUR);
	#endif

	if (transparentAlpha > 0.001) {
		#ifdef ALT_GLASS
			if (id == 2) {
				vec3 transColor = transparent.rgb / transparentAlpha;
				color *= transColor * (2.0 - transColor); //min(transColor * 2.0, 1.0); //because the default colors are too dark to be used.

				float skylight = aux2.g;
				float blocklight = aux2.r;
				float heldlight = 0.0;

				color += transColor * calcMainLightColor(blocklight, skylight, heldlight, nearPos) * 0.125 * (1.0 - blindness);
			}
			else {
		#endif
				color = mix(color, transparent.rgb / transparentAlpha, transparentAlpha);
		#ifdef ALT_GLASS
			}
		#endif
	}

	#ifdef REFLECT
		reflective *= aux2.g * aux2.g * (1.0 - blindness);
		vec3 reflectedPos;
		if (isEyeInWater == 0 && reflective > 0.001) { //sky reflections
			vec3 newnormal = mat3(gbufferModelView) * normal;
			reflectedPos = reflect(nearPos.viewNorm, newnormal);
			vec3 skyclr = calcFogColor(reflectedPos);
			float posDot = dot(-nearPos.viewNorm, newnormal);
			color += skyclr * square(square(1.0 - max(posDot, 0.0))) * reflective;
		}
	#endif

	if (id >= 1) { //everything that I've currently assigned effects to so far needs fog to be done in this stage.
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
			#ifdef FOG_ENABLED_TF
				float fogAmount = nearPos.viewDist - 0.2;
				if (fogAmount > 0.0) {
					fogAmount = fogify(fogAmount * exp2(1.5 - nearPos.world.y * 0.015625), FOG_DISTANCE_MULTIPLIER_TF);
					color = mix(calcFogColor(nearPos.viewNorm) * min(max(aux2.g * 2.0, eyeBrightness.y / 120.0), 1.0) * (1.0 - blindness), color, fogAmount);
					#if defined(BLUR_ENABLED) && WATER_BLUR != 0
						waterBlur *= fogAmount;
					#endif
				}
			#endif
		}
	}

	color = min(color, 1.0); //reflections (And possibly other things) can go above maximum brightness

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