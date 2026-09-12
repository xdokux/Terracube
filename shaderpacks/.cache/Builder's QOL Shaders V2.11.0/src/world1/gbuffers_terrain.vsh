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
		if (id == 2 || id == 3 || id == 4) { //plants and double plants
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
				ao = float(texcoord.y < mc_midTexCoord.y);
			}
		#endif

		#ifdef LAVA_PATCHES
			else if (id == 7 || id == 18) {
				isLava = 1.0;
				randCoord = (
					abs(gl_Normal.y) > 0.1
					? worldPos.xz * 2.0
					: vec2((worldPos.x + worldPos.z) * 4.0, worldPos.y + frameTimeCounter)
				);
			}
		#endif
		else if (id == 20) { //soul fire
			normal = vec3(0.0, 1.0, 0.0);

			lmcoord.x = 29.0 / 32.0;
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