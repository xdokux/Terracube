#version 120

#include "lib/defines.glsl"

attribute vec2 mc_midTexCoord;
attribute vec3 mc_Entity;

uniform float frameTimeCounter;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;

varying float ao;
varying float isLava;
varying vec2 lmcoord;
varying vec2 randCoord;
varying vec2 texcoord;
varying vec4 tint;

#include "/lib/noiseres.glsl"

#include "lib/magicNumbers.glsl"

#if LAVA_WAVE_STRENGTH != 0
	float lavaWave(vec2 pos) {
		pos *= invNoiseRes;
		float offset = 0.875;
		offset += cos(texture2D(noisetex, pos / 30.0).r * 25.0 + frameTimeCounter) * 0.5;
		offset += cos(texture2D(noisetex, pos / 20.0).r * 12.5 + frameTimeCounter * 1.5) * 0.375;
		return offset * (float(LAVA_WAVE_STRENGTH) / 100.0 / 1.75);
	}
#endif

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	vec3 vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vec3 vPosPlayer = mat3(gbufferModelViewInverse) * vPosView;
	vec3 worldPos = vPosPlayer + actualCameraPosition;
	vec3 normal = gl_Normal;

	tint = gl_Color;

	ao = 1.0;
	isLava = 0.0;

	//Using IDs above 10000 to represent all blocks that I care about
	//if the ID is less than 10000, then I don't need to do extra logic to see if it has special effects.
	if (mc_Entity.x > 10000.0) {
		int id = int(mc_Entity.x) - 10000;
		if (id == 7) { //lava
			lmcoord.x = 0.96875; //hide vanilla lighting glitches
			isLava = 1.0;

			#if LAVA_WAVE_STRENGTH != 0
				if (worldPos.y <= NETHER_LAVA_LEVEL + 0.01) {
					worldPos.y -= lavaWave(worldPos.xz + 0.5) * fract(worldPos.y - 0.01); // + 0.5 to avoid sharp edges in lava displacement when the coords are on the edge of a noisetex pixel
				}
			#endif

			#ifdef LAVA_PATCHES
				if (abs(normal.y) > 0.1) randCoord = worldPos.xz * 0.5;
				else randCoord = vec2((worldPos.x + worldPos.z) * 4.0, worldPos.y + frameTimeCounter);
			#endif
		}
		/*
		#ifdef LAVA_PATCHES
		#endif
		#ifdef SOUL_LAVA
		#endif
		*/
		#if defined(LAVA_PATCHES) || defined(SOUL_LAVA)
			else if (id == 18) { //magma
				isLava = 1.0;
				randCoord = (
					abs(gl_Normal.y) > 0.1
					? worldPos.xz * 0.5
					: vec2((worldPos.x + worldPos.z) * 4.0, worldPos.y + frameTimeCounter)
				);
			}
		#endif
		else if (id == 2 || id == 3 || id == 4) { //plants and double plants
			normal = vec3(0.0, 1.0, 0.0);

			#ifdef GRASS_AO
				ao = float(texcoord.y < mc_midTexCoord.y);
				if (id != 2) ao = (ao + float(id == 4)) * 0.5;
			#endif

			#ifdef REMOVE_Y_OFFSET
				worldPos.y = floor(worldPos.y + 0.5);
			#endif
			#ifdef REMOVE_XZ_OFFSET
				worldPos.xz = floor(worldPos.xz + 0.5);
			#endif
		}
		#ifdef GRASS_AO
			else if (id == 5) { //crops
				normal = vec3(0.0, 1.0, 0.0);

				ao = float(texcoord.y < mc_midTexCoord.y);
			}
		#endif
		else if (id == 20) { //soul fire
			normal = vec3(0.0, 1.0, 0.0);

			lmcoord.x = 29.0 / 32.0;
		}
		else if (id == 21) { //mushrooms and other sturdy plants
			normal = vec3(0.0, 1.0, 0.0);

			#ifdef GRASS_AO
				//mushrooms are kind of short, so multiply by 2
				//to make the AO start at half the block height.
				ao = float(texcoord.y < mc_midTexCoord.y) * 2.0;
			#endif
		}
		else if (id == 8) { //shadeless blocks
			normal = vec3(0.0, 1.0, 0.0);
		}
		#ifdef JUMPING_DRAGON_EGGS
			else if (id == 19) { //dragon eggs
				#include "/lib/dragonEgg.glsl"
			}
		#endif
	}

	vPosPlayer = worldPos - actualCameraPosition;
	vPosView = mat3(gbufferModelView) * vPosPlayer;
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);

	float glmult = dot(vec4(abs(normal.x), abs(normal.z), max(normal.y, 0.0), max(-normal.y, 0.0)), vec4(0.6, 0.8, 1.0, 0.5));
	glmult = mix(glmult, 1.0, lmcoord.x * lmcoord.x); //increase brightness when block light is high
	tint.rgb *= glmult;
}