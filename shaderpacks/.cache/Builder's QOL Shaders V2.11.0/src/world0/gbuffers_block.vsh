#version 120

#include "lib/defines.glsl"

uniform float night;
uniform float rainStrength;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosNorm;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec3 vPosPlayer;
varying vec3 vPosView;
varying vec4 tint;

void main() {
	vPosView    = (gl_ModelViewMatrix  * gl_Vertex).xyz;
	vPosPlayer  = mat3(gbufferModelViewInverse) * vPosView;
	gl_Position =  gl_ProjectionMatrix * vec4(vPosView, 1.0);

	texcoord    = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord     = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	tint     =  gl_Color;

	vec3 normal = normalize(gl_NormalMatrix * gl_Normal);
	#include "lib/glmult.glsl"
}