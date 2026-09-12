#version 120

#include "lib/defines.glsl"

uniform bool isSpectator;
uniform float aspectRatio;
uniform float blindness;
uniform float darknessLightFactor;
uniform float far;
uniform float fov;
uniform float frameTimeCounter;
uniform float inBasaltDeltas;
uniform float inSoulSandValley;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform int bedrockLevel = 0;
uniform int isEyeInWater;
uniform int logicalHeightLimit = 128;
uniform ivec2 eyeBrightnessSmooth;
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
#ifdef IS_IRIS
	uniform vec3 eyePosition;
#else
	vec3 eyePosition = actualCameraPosition;
#endif
uniform vec3 fogColor;

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

#include "lib/magicNumbers.glsl"

#include "/lib/goldenOffsets.glsl"

#include "/lib/math.glsl"

#include "/lib/heatRefraction.glsl"

#include "lib/calcMainLightColor.glsl"

#include "lib/calcFogColor.glsl"

#include "/lib/noiseLOD.glsl"

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

	vec2 tc = texcoord + heatRefractionOffset() * mix(HEAT_REFRACTION, heatRefractionInBasaltDeltas, inBasaltDeltas);

	vec3 normal = texture2D(gnormal, tc).rgb * 2.0 - 1.0;
	int id = int(texture2D(gaux2, tc).b * 10.0 + 0.1);

	Position nearPos = posFromDepthtex(depthtex0);

	float blur = 0.0;

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		blur = interpolateSmooth1(min(abs(nearPos.blockDist - dofDistance) / dofDistance, 1.0)) * float(DOF_STRENGTH);
	#endif

	if (id == 1) { //water
		#if defined(BLUR_ENABLED) && WATER_BLUR != 0
			blur = max(blur, float(WATER_BLUR));
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

			vec2 offset = waterNoiseLOD(vec2(newPos[swizzles[0]], newPos[swizzles[1]]), nearPos.blockDist) / 64.0; //witchcraft
			vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio) / max(nearPos.blockDist * 0.0625, 1.0);
			vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
			if (dot(normal, newnormal) > 0.9) { //don't offset on the edges of water
				tc = newtc;
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
			if (dot(normal, newnormal) > 0.9) tc = newtc;
		#endif
	}

	if (id != int(texture2D(gaux2, tc).b * 10.0 + 0.1)) tc = texcoord;

	vec4 c = texture2D(gcolor, tc);
	vec3 color = c.rgb;
	vec4 transparent = texture2D(composite, tc);
	float transparentAlpha = c.a; //using gcolor to store composite's alpha.

	if (transparentAlpha > 0.001) {
		#ifdef ALT_GLASS
			if (id == 2) {
				vec3 transColor = transparent.rgb / transparentAlpha;
				color *= transColor * (2.0 - transColor); //min(transColor * 2.0, 1.0); //because the default colors are too dark to be used.

				float blocklight = texture2D(gaux2, tc).r;
				float heldlight = 0.0;

				color = min(color + transColor * calcMainLightColor(blocklight, heldlight, nearPos) * 0.125 * (1.0 - blindness), 1.0);

				#ifdef FOG_ENABLED_NETHER
					vec3 fogclr = calcFogColor(nearPos.playerNorm);
					color = mix(
						fogclr,
						color,
						exp2(
							nearPos.viewDist
							* exp2(
								abs(nearPos.world.y - (bedrockLevel + logicalHeightLimit))
								* (-4.0 / logicalHeightLimit)
								+ 4.0
							)
							* -FOG_DENSITY_MULTIPLIER_NETHER
						)
					);
				#endif
			}
			else
		#endif
				color = mix(color, transparent.rgb / transparentAlpha, transparentAlpha);
	}

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