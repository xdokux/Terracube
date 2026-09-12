#version 120

#include "lib/defines.glsl"

uniform bool isSpectator;
uniform float blindness;
uniform float darknessLightFactor;
uniform float far;
uniform float fov;
uniform float frameTimeCounter;
uniform float inSoulSandValley;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform int bedrockLevel = 0;
uniform int logicalHeightLimit = 128;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D depthtex1;
uniform sampler2D gaux1;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
#define lightmap gaux4
uniform sampler2D gcolor;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
#ifdef IS_IRIS
	uniform vec3 eyePosition;
#else
	vec3 eyePosition = actualCameraPosition;
#endif
uniform vec3 fogColor;

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

const int gaux3Format     = RGBA16;
const int gcolorFormat    = RGBA16;
const int compositeFormat = RGBA16;
const int gnormalFormat   = RGB16;
*/

#include "/lib/noiseres.glsl"

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "lib/calcMainLightColor.glsl"

#include "lib/calcFogColor.glsl"

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

	//position of opaque geometry.
	//must be named "pos" for cross processing.
	Position pos = posFromDepthtex(depthtex1);

	vec3 color = texture2D(gcolor, tc).rgb;

	#ifdef FOG_ENABLED_NETHER
		vec3 fogclr = calcFogColor(pos.playerNorm);
	#else
		vec3 fogclr = fogColor;
	#endif

	if (pos.isSky) {
		color = fogclr * (1.0 - blindness);
	}
	else {
		vec4 aux = texture2D(gaux1, tc);
		float blocklight = aux.r;
		float heldlight = 0.0;

		color *= calcMainLightColor(blocklight, heldlight, pos);

		vec2 lmcoord = aux.rg;

		#include "lib/crossprocess.glsl"

		#ifdef FOG_ENABLED_NETHER
			color = mix(
				fogclr,
				color,
				exp2(
					pos.viewDist
					* exp2(
						abs(pos.world.y - (bedrockLevel + logicalHeightLimit))
						* (-4.0 / logicalHeightLimit)
						+ 4.0
					)
					* -FOG_DENSITY_MULTIPLIER_NETHER
				)
			);
		#endif

		if (blindness > 0.0) color *= interpolateSmooth1(max(1.0 - pos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);
	}

/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(color, texture2D(gaux3, texcoord).r); //gcolor
}