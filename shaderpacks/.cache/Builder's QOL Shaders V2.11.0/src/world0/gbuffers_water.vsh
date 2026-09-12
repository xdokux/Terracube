#version 120

#include "lib/defines.glsl"

attribute vec3 mc_Entity;

uniform float adjustedTime;
uniform float day;
uniform float frameTimeCounter;
uniform float night;
uniform float phase;
uniform float rainStrength;
uniform float sunset;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunPosNorm;

varying float mcentity; //ID data of block currently being rendered.
varying vec2 lmcoord;
varying vec2 texcoord;
varying vec3 normal;
varying vec3 shadowColor; //Color of shadows. Sky-colored, to simulate indirect lighting.
varying vec3 skyLightColor; //Color of sky light. Is usually white during the day, and very dark blue at night.
varying vec3 vPosPlayer;
varying vec3 vPosView;
varying vec4 tint;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

#include "/lib/noiseres.glsl"

#include "lib/magicNumbers.glsl"

#include "/lib/calcHeldLightColor.glsl"

#if WATER_WAVE_STRENGTH != 0
	float waterWave(vec2 pos) {
		pos *= invNoiseRes;
		float offset = 0.875;
		offset += cos(texture2D(noisetex, pos / 20.0).r * 25.0 + frameTimeCounter * 2.0) * 0.5;
		offset += cos(texture2D(noisetex, pos / 15.0).r * 12.5 + frameTimeCounter * 3.0) * 0.375;
		return offset * (float(WATER_WAVE_STRENGTH) / 100.0 / 1.75);
	}
#endif

void main() {
	vPosView   = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vPosPlayer = mat3(gbufferModelViewInverse) * vPosView;
	texcoord   = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord    = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	tint       =  gl_Color;
	mcentity   = 0.1;
	vec3 worldPos = vPosPlayer + actualCameraPosition;

	//Using IDs above 10000 to represent all blocks that I care about
	//if the ID is less than 10000, then I don't need to do extra logic to see if it has special effects.
	if (mc_Entity.x > 10000.0) {
		int id = int(mc_Entity.x) - 10000;
		if (id == 9) { //water
			mcentity = 1.1;
			#if WATER_WAVE_STRENGTH != 0
				if (worldPos.y <= SEA_LEVEL + 0.01 && worldPos.y >= SEA_LEVEL - 0.99) {
					worldPos.y -= waterWave(worldPos.xz + 0.5) * fract(worldPos.y - 0.01); // + 0.5 to avoid sharp edges in lava displacement when the coords are on the edge of a noisetex pixel
				}
			#endif
		}
		else if (id == 10) mcentity = 2.1; //stained glass
		else if (id == 11) mcentity = 3.1; //ice
	}

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif

	#include "lib/colors.glsl"

	normal = gl_NormalMatrix * gl_Normal;
	#include "lib/glmult.glsl"
	normal = gl_Normal * 0.5 + 0.5;

	vPosPlayer = worldPos - actualCameraPosition;
	vPosView = mat3(gbufferModelView) * vPosPlayer;
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);
}