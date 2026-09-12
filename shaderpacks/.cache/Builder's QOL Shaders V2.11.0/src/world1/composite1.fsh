#version 120

#include "lib/defines.glsl"

uniform bool isSpectator;
uniform float aspectRatio;
uniform float blindness;
uniform float darknessLightFactor;
uniform float far;
uniform float fogEnd;
uniform float fov;
uniform float frameTimeCounter;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D composite;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
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
//required on older versions of optifine for its option-parsing logic:
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

#ifdef VOID_CLOUDS
	#include "/lib/hue.glsl"

	#include "lib/drawVoidClouds.glsl"
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

	vec3 normal = texture2D(gnormal, tc).rgb * 2.0 - 1.0;
	int id = int(texture2D(gaux2, tc).b * 10.0 + 0.1);

	Position nearPos = posFromDepthtex(depthtex0);

	float blur = 0.0;

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		blur = interpolateSmooth1(min(abs(nearPos.blockDist - dofDistance) / dofDistance, 1.0)) * float(DOF_STRENGTH);
	#endif

	#ifdef VOID_CLOUDS
		bool isTCOffset = false; //tracks weather or not void cloud positions need to be re-calculated due to water/ice refractions
	#endif

	if (id == 1) { //water
		#if defined(BLUR_ENABLED) && WATER_BLUR != 0
			blur = max(blur, WATER_BLUR);
		#endif

		#ifdef WATER_REFRACT
			vec3 newPos = nearPos.world;
			ivec2 swizzles;
			if (abs(normal.y) > 0.1) { //top/bottom surface
				if (abs(normal.y) < 0.999) newPos.xz -= normalize(normal.xz) * frameTimeCounter * 3.0;
				swizzles = ivec2(0, 2);
			}
			else {
				newPos.y += frameTimeCounter * 4.0;
				if (abs(normal.x) < 0.02) swizzles = ivec2(0, 1);
				else swizzles = ivec2(2, 1);
			}

			vec2 offset = waterNoiseLOD(vec2(newPos[swizzles[0]], newPos[swizzles[1]]), nearPos.blockDist) / 64.0; //witchcraft.
			vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio) / max(nearPos.blockDist * 0.0625, 1.0);
			vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
			if (dot(normal, newnormal) > 0.9) { //don't offset on the edges of water
				tc = newtc;

				#ifdef VOID_CLOUDS
					isTCOffset = true;
				#endif
			}
		#endif
	}
	else if (id == 2) { //stained glass
		#if defined(BLUR_ENABLED) && GLASS_BLUR != 0
			blur = max(blur, float(GLASS_BLUR));
		#endif
	}
	else if (id == 3 || id == 4) { //ice and held ice
		#if defined(BLUR_ENABLED) && ICE_BLUR != 0
			blur = max(blur, float(ICE_BLUR));
		#endif

		#ifdef ICE_REFRACT
			vec3 offset;
			if (id == 3) {
				vec2 coord = (abs(normal.y) < 0.001 ? vec2(nearPos.world.x + nearPos.world.z, nearPos.world.y) : nearPos.world.xz);
				offset = iceNoiseLOD(coord * 256.0, nearPos.blockDist) / 128.0;
			}
			else {
				vec2 coord = gl_FragCoord.xy + 0.5;
				offset = iceNoise(coord * 0.5) / 128.0;
			}

			vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio);
			vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
			if (dot(normal, newnormal) > 0.9) {
				tc = newtc;

				#ifdef VOID_CLOUDS
					isTCOffset = true;
				#endif
			}
		#endif
	}

	if (id != int(texture2D(gaux2, tc).b * 10.0 + 0.1)) {
		tc = texcoord;
		#ifdef VOID_CLOUDS
			isTCOffset = false;
		#endif
	}

	#ifdef VOID_CLOUDS
		float cloudDiff = VOID_CLOUD_HEIGHT - actualCameraPosition.y;
		vec3 baseCloudPos = nearPos.player;
		float cloudDist;
		vec4 cloudclr = vec4(0.0);
		//don't render clouds below you if you're below them, and vise versa.
		bool cloudy = sign(cloudDiff) == sign(baseCloudPos.y);

		if (cloudy) {
			//calculate base cloud plane position
			baseCloudPos = normalize(baseCloudPos);
			baseCloudPos = vec3(baseCloudPos.xz / baseCloudPos.y * cloudDiff, cloudDiff).xzy;
			cloudDist = lengthSquared3(baseCloudPos) * 0.999; //avoid z-fighting by making clouds a little bit closer
			float opacityModifier = -1.0;
			//additional logic if there's terrain in front of the clouds (used for fake volumetric effects)
			if (!nearPos.isSky && square(nearPos.blockDist) < cloudDist) {
				opacityModifier = abs(nearPos.world.y - VOID_CLOUD_HEIGHT) / 4.0;
				if (opacityModifier < 1.0) { //maximum cloud density
					baseCloudPos = nearPos.player;
					cloudDist = lengthSquared3(baseCloudPos) * 0.999;
				}
				else { //pos is outside range of fake volumetric effects, check pos1 next.
					opacityModifier = -1.0;
					Position farPos = posFromDepthtex(depthtex1);
					if (!farPos.isSky) { //opaque object exists here
						opacityModifier = abs(farPos.world.y - VOID_CLOUD_HEIGHT) / 4.0;
						if (opacityModifier < 1.0 && farPos.blockDist < cloudDist) { //within volumetric range
							baseCloudPos = farPos.player;
							cloudDist = lengthSquared3(baseCloudPos) * 0.999;
						}
						else opacityModifier = -1.0;
						cloudy = farPos.blockDist > cloudDist; //true if there's clouds between the terrain and the transparent thing
					} //opaque object exists here too
				} //pos is outside range of fake volumetric effects, check pos1 next.
			} //something in front of terrain

			if (cloudy) {
				if (isTCOffset && square(nearPos.blockDist) < cloudDist) { //re-calculate position to account for water refraction.
					vec4 recalculated = gbufferProjectionInverse * vec4(tc * 2.0 - 1.0, 1.0, 1.0);
					recalculated.xyz /= recalculated.w;
					recalculated.xyz = normalize(mat3(gbufferModelViewInverse) * recalculated.xyz);
					baseCloudPos = vec3(recalculated.xz / recalculated.y * cloudDiff, cloudDiff).xzy;
					//not re-calculating distance because it's not really all that necessary.
				}
				cloudDist = sqrt(cloudDist);
				cloudclr = drawVoidClouds(baseCloudPos, opacityModifier); //opacityModifier is -1.0 when not applying volumetric effects

				if (cloudclr.a > 0.001) {
					if (opacityModifier > 0.001 && opacityModifier < 0.999) { //in the fadeout range
						cloudclr.a *= interpolateSmooth1(opacityModifier);
					}
				}
				else cloudy = false; //no need to render clouds that don't exist at this location
			}
		}
	#endif

	vec4 c = texture2D(gcolor, tc);
	vec3 color = c.rgb;
	vec4 transparent = texture2D(composite, tc);
	float transparentAlpha = c.a; //using gcolor to store composite's alpha.

	if (transparentAlpha > 0.0) {
		#ifdef VOID_CLOUDS
			if (cloudy && nearPos.blockDist < cloudDist) color = mix(color, cloudclr.rgb, cloudclr.a);
		#endif

		#ifdef ALT_GLASS
			if (id == 2) {
				vec3 transColor = transparent.rgb / transparentAlpha;
				color *= transColor * (2.0 - transColor); //min(transColor * 2.0, 1.0); //because the default colors are too dark to be used.

				float blocklight = texture2D(gaux2, tc).r;
				float heldlight = 0.0;

				color = min(color + transColor * calcMainLightColor(blocklight, heldlight, nearPos) * 0.125 * (1.0 - blindness), 1.0);

				#ifdef FOG_ENABLED_END
					color.rgb = mix(
						fogColor * (1.0 - nightVision * 0.5),
						color.rgb,
						fogify(nearPos.blockDist / fogEnd, FOG_DISTANCE_MULTIPLIER_END)
					);
				#endif
			}
			else {
		#endif
				color = mix(color, transparent.rgb / transparentAlpha, transparentAlpha);
		#ifdef ALT_GLASS
			}
		#endif
	}
	#ifdef VOID_CLOUDS
		else if (cloudy) {
			if (nearPos.blockDist < cloudDist || id != 1) color = mix(color, cloudclr.rgb, cloudclr.a);
		}

		if (cloudy && (id == 1 || transparentAlpha > 0.001) && nearPos.blockDist > cloudDist) color = mix(color, cloudclr.rgb, cloudclr.a);
		color = mix(color, voidCloudInsideColor.rgb, voidCloudInsideColor.a);
	#endif

	#if defined(BLUR_ENABLED) && UNDERWATER_BLUR != 0
		if (isEyeInWater == 1) blur = float(UNDERWATER_BLUR);
	#endif

	#ifdef BLUR_ENABLED
		blur /= 256.0;
	#endif

	color *= mix(vec3(eyeAdjust), vec3(1.0), color);

/* DRAWBUFFERS:6 */
	gl_FragData[0] = vec4(color, 1.0 - blur); //gcolor
}