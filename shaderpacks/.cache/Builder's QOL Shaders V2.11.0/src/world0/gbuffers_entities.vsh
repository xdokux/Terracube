#version 120

#include "lib/defines.glsl"

uniform float night;
uniform float rainStrength;
uniform vec3 sunPosNorm;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 tint;

void main() {
	//match logic from gbuffers_armor_glint.vsh
	vec3 vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	tint  =  gl_Color;

	//not pre-normalized for item frames with maps in them
	vec3 normal = normalize(gl_NormalMatrix * gl_Normal);
	#include "lib/glmult.glsl"
}