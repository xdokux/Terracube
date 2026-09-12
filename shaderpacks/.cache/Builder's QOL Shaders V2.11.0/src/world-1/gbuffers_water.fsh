#version 120

#include "lib/defines.glsl"

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
uniform sampler2D lightmap;
uniform sampler2D noisetex;
uniform sampler2D texture;
uniform vec3 actualCameraPosition;
#ifdef IS_IRIS
	uniform vec3 eyePosition;
#else
	vec3 eyePosition = actualCameraPosition;
#endif
uniform vec3 fogColor;

varying float mcentity; //ID data of block currently being rendered.
varying vec2 lmcoord;
varying vec2 texcoord;
varying vec3 normal;
varying vec3 vPosPlayer;
varying vec3 vPosView;
varying vec4 tint;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

struct Position {
	vec3 view;
	vec3 player;
	vec3 playerNorm;
	vec3 world;
	float blockDist;
	float viewDist;
};

#include "/lib/noiseres.glsl"

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "lib/calcMainLightColor.glsl"

#include "lib/calcFogColor.glsl"

void main() {
	vec4 color = texture2D(texture, texcoord) * tint;

	int id = int(mcentity);

	#ifdef CLEAR_WATER
		if (id == 1) {
			color.a = 0.0;
		}
		else {
	#endif
			#ifdef ALT_GLASS
				bool applyEffects = true;
				if (id == 2) {
					if (color.a > THRESHOLD_ALPHA) {
						color.a = 1.0; //make borders opaque
						id = 0;
					}
					else {
						applyEffects = false; //don't apply lighting effects to the centers of glass
					}
				}
			#else
				if (id == 2 && color.a > THRESHOLD_ALPHA) id = 0;
			#endif

			#ifdef ALT_GLASS
				if (applyEffects) {
			#endif
					Position pos;
					pos.view = vPosView;
					pos.player = vPosPlayer;
					pos.world = vPosPlayer + actualCameraPosition;
					pos.blockDist = length(pos.view);
					pos.viewDist = pos.blockDist / far;
					pos.playerNorm = pos.player / pos.blockDist;

					float blocklight = lmcoord.x;
					float heldlight = 0.0;

					color.rgb *= calcMainLightColor(blocklight, heldlight, pos);

					#include "lib/crossprocess.glsl"

					#ifdef FOG_ENABLED_NETHER
						color.rgb = mix(
							calcFogColor(pos.playerNorm),
							color.rgb,
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

					if (blindness > 0.0) color.rgb *= interpolateSmooth1(max(1.0 - pos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);

			#ifdef ALT_GLASS
				}
			#endif
	#ifdef CLEAR_WATER
		}
	#endif

/* DRAWBUFFERS:2563 */
	gl_FragData[0] = vec4(normal, 1.0); //gnormal
	gl_FragData[1] = vec4(lmcoord, id * 0.1, 1.0); //gaux2
	gl_FragData[2] = vec4(1.0, 0.0, 0.0, color.a); //gaux3
	gl_FragData[3] = color; //gcolor
}