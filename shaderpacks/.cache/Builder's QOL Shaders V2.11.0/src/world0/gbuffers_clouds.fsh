#version 120

#include "lib/defines.glsl"

uniform float adjustedTime;
uniform float blindness;
uniform float day;
uniform float far;
uniform float night;
uniform float nightVision;
uniform float rainStrength;
uniform float sunset;
uniform float wetness;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform sampler2D texture;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunPosNorm;
uniform vec3 upPosNorm;

varying vec2 texcoord;
varying vec3 normal;
varying vec3 vPosPlayer;
varying vec3 vPosView;
varying vec4 tint;

struct Position {
	vec3 view;
	vec3 viewNorm;
	vec3 player;
	vec3 world;
	float blockDist;
	float viewDist;
};

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "lib/calcFogAmount.glsl"

#include "lib/calcFogColor.glsl"

void main() {
	vec4 color = texture2D(texture, texcoord) * tint;
	if (color.a < 0.1) discard; //abort early if possible.

	#ifdef FOG_ENABLED_OVERWORLD
		Position pos;
		pos.view = vPosView;
		pos.player = vPosPlayer;
		pos.world = vPosPlayer + actualCameraPosition;
		pos.blockDist = length(pos.view);
		pos.viewDist = pos.blockDist / far;
		pos.viewNorm = pos.view / pos.blockDist;

		color.rgb = mix(calcFogColor(pos.viewNorm), color.rgb, calcFogAmount(pos, pos.viewDist));
	#endif

	color.rgb *= 1.0 - blindness;

/* DRAWBUFFERS:2563 */
	gl_FragData[0] = vec4(normal, 1.0); //gnormal
	gl_FragData[1] = vec4(0.0, 1.0, 0.0, 1.0); //gaux2
	gl_FragData[2] = vec4(1.0, 0.0, 0.0, color.a); //gaux3
	gl_FragData[3] = color; //gcolor
}