#version 120

#include "lib/defines.glsl"

attribute vec3 mc_Entity;

uniform float frameTimeCounter;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform mat4 gbufferModelViewInverse;
uniform sampler2D noisetex;

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

#include "/lib/noiseres.glsl"

#include "/lib/calcHeldLightColor.glsl"

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	tint     = gl_Color;

	vPosView    = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vPosPlayer  = mat3(gbufferModelViewInverse) * vPosView;
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);
	normal      = gl_Normal * 0.5 + 0.5;
	mcentity    = 0.1;

	//Using IDs above 10000 to represent all blocks that I care about
	//if the ID is less than 10000, then I don't need to do extra logic to see if it has special effects.
	if (mc_Entity.x > 10000.0) {
		int id = int(mc_Entity.x) - 10000;
		if      (id == 9)  mcentity = 1.1; //water
		else if (id == 10) mcentity = 2.1; //stained glass
		else if (id == 11) mcentity = 3.1; //ice
	}

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif
}