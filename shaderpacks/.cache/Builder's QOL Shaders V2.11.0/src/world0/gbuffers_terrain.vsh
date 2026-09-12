#version 120

#include "lib/defines.glsl"

attribute vec2 mc_midTexCoord;
attribute vec3 mc_Entity;

uniform float frameTimeCounter;
uniform float night;
uniform float rainStrength;
uniform float wetness;
uniform int bedrockLevel = 0;
uniform int logicalHeightLimit = 384;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
uniform vec3 sunPosNorm;

varying float ao;
varying float isDirt;
varying float isLava;
varying vec2 lmcoord;
varying vec2 randCoord;
varying vec2 texcoord;
varying vec4 tint;

#include "/lib/noiseres.glsl"

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

vec3 windOffset(vec3 worldPos, float multiplier, float speed) {
	float baseWindAmt = min(rainStrength, wetness) * 1.5 + ((worldPos.y - bedrockLevel) / logicalHeightLimit * 1.5 + 0.5) * (1.0 - night * 0.5); //1.0x at y=64, 2.0x at y=256, and rain increases this to 2.5x at y=64 and 3.5x at y=256. Rain also increases it by 1.5x, and night decreases it to 0.5x.
	vec3 waveStart = texture2D(noisetex, vec2(worldPos.x + frameTimeCounter, worldPos.z) * (0.375 * invNoiseRes)).rgb; //oscillation direction and phase offset
	float waveMultiplier = texture2D(noisetex, vec2(worldPos.x * 0.125 + frameTimeCounter * 0.5, worldPos.z * 0.125) * invNoiseRes).r * 0.5 + 0.5; //multiplier to add variety
	vec2 offset = vec2(waveStart.y * 0.4 - 0.2, waveStart.z * 0.2 - 0.1) * cos(waveStart.x * 6.283185307 + frameTimeCounter * speed) * waveMultiplier; //combine to get position offset
	offset.x -= baseWindAmt * 0.01 + 0.02; //biased towards east wind
	offset *= multiplier * baseWindAmt; //scale offset
	return vec3(offset.x, 0.5 / (lengthSquared2(offset) + 0.5) - 1.0, offset.y); //move vertexes down some based on how much they were offset
}

//simpler version which doesn't take elevation or rain strength into account.
vec3 windOffsetWater(vec3 worldPos, float multiplier, float speed) {
	vec3 waveStart = texture2D(noisetex, vec2(worldPos.x + frameTimeCounter, worldPos.z) * (0.375 * invNoiseRes)).rgb; //oscillation direction and phase offset
	float waveMultiplier = texture2D(noisetex, vec2(worldPos.x * 0.125 + frameTimeCounter * 0.5, worldPos.z * 0.125) * invNoiseRes).r * 0.5 + 0.5; //multiplier to add variety
	vec2 offset = vec2(waveStart.y - 0.5, waveStart.z * 0.5 - 0.25) * cos(waveStart.x * 6.283185307 + frameTimeCounter * speed) * waveMultiplier; //combine to get worldPosition offset
	offset.x -= 0.02; //biased towards east wind
	offset *= multiplier;
	return vec3(offset.x, 0.5 / (lengthSquared2(offset) + 0.5) - 1.0, offset.y); //move vertexes down some based on how much they were offset
}

#ifdef GRASS_PATCHES
	float noiseMap(vec2 worldPos) {
		float noise = 0.0;
		noise += texture2D(noisetex, worldPos * (invNoiseRes * 0.03125)).r;
		noise += texture2D(noisetex, worldPos * (invNoiseRes * 0.09375)).r * 0.5;
		noise += texture2D(noisetex, worldPos * (invNoiseRes * 0.375  )).r * 0.25;
		return noise;
	}
#endif

#if WATER_WAVE_STRENGTH != 0
	float waterWave(vec2 worldPos) {
		float offset = 0.875;
		offset += cos(texture2D(noisetex, worldPos * (invNoiseRes / 20.0)).r * 25.0 + frameTimeCounter * 2.0) * 0.5;
		offset += cos(texture2D(noisetex, worldPos * (invNoiseRes / 15.0)).r * 12.5 + frameTimeCounter * 3.0) * 0.375;
		return offset * (float(WATER_WAVE_STRENGTH) / 100.0 / 1.75);
	}
#endif

void main() {
	ao = 1.0;
	isLava = 0.0;
	isDirt = 0.0;

	bool isGrass = false;

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;

	vec3 vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vec3 vPosPlayer = mat3(gbufferModelViewInverse) * vPosView;
	vec3 worldPos = vPosPlayer + actualCameraPosition;

	tint = gl_Color;

	vec3 normal;
	//Using IDs above 10000 to represent all blocks that I care about
	//if the ID is less than 10000, then I don't need to do extra logic to see if it has special effects.
	if (mc_Entity.x > 10000.0) {
		int id = int(mc_Entity.x) - 10000;
		if (id == 1) { //grass blocks and dirt
			normal = gl_NormalMatrix * gl_Normal;

			#ifdef GRASS_PATCHES
				isGrass = gl_Color.g > gl_Color.b;
			#endif

			#ifdef WET_DIRT
				isDirt = float(abs(gl_Color.g - gl_Color.b) < 0.02);
			#endif
		}
		else if (id == 2) { //tallgrass and other plants
			normal = gl_NormalMatrix[1];

			#ifdef REMOVE_Y_OFFSET
				worldPos.y = floor(worldPos.y + 0.5);
			#endif
			#ifdef REMOVE_XZ_OFFSET
				worldPos.xz = floor(worldPos.xz + 0.5);
			#endif

			#if defined(GRASS_AO) || defined(WAVING_GRASS)
				float amt = float(texcoord.y < mc_midTexCoord.y);
				#ifdef GRASS_AO
					ao = amt;
				#endif

				#ifdef WAVING_GRASS
					if (amt > 0.1) { //will always either be 0.0 or 1.0
						worldPos += windOffset(worldPos, amt * lmcoord.y * lmcoord.y, 5.0);
					}
				#endif
			#endif

			#ifdef GRASS_PATCHES
				isGrass = gl_Color.g > gl_Color.b; //some double plants are colored by texture, and others are colored by biome.
			#endif
		}
		else if (id == 3 || id == 4) { //double plants
			normal = gl_NormalMatrix[1];

			#ifdef REMOVE_Y_OFFSET
				worldPos.y = floor(worldPos.y + 0.5);
			#endif
			#ifdef REMOVE_XZ_OFFSET
				worldPos.xz = floor(worldPos.xz + 0.5);
			#endif

			#if defined(GRASS_AO) || defined(WAVING_GRASS)
				float amt = (float(texcoord.y < mc_midTexCoord.y) + float(id == 4)) * 0.5;
				#ifdef GRASS_AO
					ao = amt;
				#endif

				#ifdef WAVING_GRASS
					amt *= 1.5;
				#endif

				#ifdef WAVING_GRASS
					if (amt > 0.1) { //will always either be 0.0, 0.5 or 1.0
						worldPos += windOffset(worldPos, amt * lmcoord.y * lmcoord.y, 3.0);
					}
				#endif
			#endif

			#ifdef GRASS_PATCHES
				isGrass = gl_Color.g > gl_Color.b; //some double plants are colored by texture, and others are colored by biome.
			#endif
		}
		#ifdef WAVING_LEAVES
			else if (id == 13) { //leaves
				normal = gl_NormalMatrix * gl_Normal;
				worldPos += windOffset(worldPos, lmcoord.y * lmcoord.y, 3.0);
			}
		#endif
		#ifdef WAVING_VINES
			else if (id == 14) { //vines
				normal = gl_NormalMatrix * gl_Normal;
				worldPos += windOffset(worldPos, lmcoord.y * lmcoord.y, 3.0);
			}
		#endif
		else if (id == 5) { //crops
			normal = gl_NormalMatrix[1];

			#ifdef GRASS_AO
				ao = float(texcoord.y < mc_midTexCoord.y);
			#endif

			#ifdef WAVING_GRASS
				if (texcoord.y < mc_midTexCoord.y) {
					worldPos += windOffset(worldPos, lmcoord.y * lmcoord.y, 5.0);
				}
			#endif
		}
		else if (id == 15) { //seagrass
			normal = gl_NormalMatrix[1];

			#ifdef WAVING_GRASS
				if (texcoord.y < mc_midTexCoord.y) {
					worldPos += windOffsetWater(worldPos, 1.0, 2.0);
				}
			#endif
		}
		else if (id == 16 || id == 17) { //tall seagrass
			normal = gl_NormalMatrix[1];

			#ifdef WAVING_GRASS
				float amt = float(texcoord.y < mc_midTexCoord.y) + float(id == 17);
				if (amt > 0.1) { //will always either be 0.0, 0.5 or 1.0
					worldPos += windOffsetWater(worldPos, amt, 1.0);
				}
			#endif
		}
		else if (id == 6) { //sugar cane
			normal = gl_NormalMatrix[1];

			#ifdef LEGACY_SUGARCANE
				tint = vec4(1.0);
			#endif

			#ifdef GRASS_PATCHES
				isGrass = true;
			#endif
		}
		else if (id == 21) { //mushrooms and other sturdy plants
			normal = gl_NormalMatrix[1];

			#ifdef GRASS_AO
				//mushrooms are kind of short, so multiply by 2
				//to make the AO start at half the block height.
				ao = float(texcoord.y < mc_midTexCoord.y) * 2.0;
			#endif
		}

		#ifdef LAVA_PATCHES
			else if (id == 7 || id == 18) { //lava or magma
				normal = gl_NormalMatrix * gl_Normal;
				isLava = 1.0;
				randCoord = (
					abs(gl_Normal.y) > 0.1
					? worldPos.xz * 2.0
					: vec2((worldPos.x + worldPos.z) * 4.0, worldPos.y + frameTimeCounter)
				);
			}
		#endif

		else if (id == 8) { //shadeless blocks
			normal = gl_NormalMatrix[1];
		}

		#if WATER_WAVE_STRENGTH != 0
			else if (id == 12) { //lily pads
				if (worldPos.y <= SEA_LEVEL + 0.99 && worldPos.y >= SEA_LEVEL - 0.01) {
					worldPos.y -= waterWave(worldPos.xz + 0.5); // + 0.5 to avoid sharp edges in lava displacement when the coords are on the edge of a noisetex pixel
				}
				normal = gl_NormalMatrix * gl_Normal;
			}
		#endif
		else if (id == 20) { //soul fire
			normal = gl_NormalMatrix[1];

			lmcoord.x = 29.0 / 32.0;
		}
		#ifdef JUMPING_DRAGON_EGGS
			else if (id == 19) { //dragon eggs
				normal = gl_Normal;

				#include "/lib/dragonEgg.glsl"

				normal = gl_NormalMatrix * normal;
			}
		#endif

		else {
			normal = gl_NormalMatrix * gl_Normal;
		}
	}
	else {
		normal = gl_NormalMatrix * gl_Normal;
	}

	#ifdef GRASS_PATCHES
		if (isGrass) {
			float noise = noiseMap(worldPos.xz) - HUMIDITY_OFFSET;
			noise = (noise - wetness * 0.125) * (wetness * -0.5 + 1.0); //more lush with less variation during rain
			if (noise > 0.0) tint.rg += vec2(noise * 0.33333333, noise * -0.125);
			else tint.rb += noise * 0.25;
			tint.g = max(tint.g, tint.r * 0.85);
		}
	#endif

	#include "lib/glmult.glsl"

	vPosPlayer = worldPos - actualCameraPosition;
	vPosView = mat3(gbufferModelView) * vPosPlayer;
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);
}