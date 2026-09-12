#version 120

#include "lib/defines.glsl"

uniform float frameTimeCounter;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform int heldItemId2;
uniform ivec2 eyeBrightnessSmooth;
uniform sampler2D noisetex;

varying float mcentity; //ID data of block currently being rendered.
varying vec2 lmcoord;
varying vec2 texcoord;
varying vec3 normal;
varying vec4 tint;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

#include "/lib/noiseres.glsl"

#include "/lib/calcHeldLightColor.glsl"

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	lmcoord.x = max(lmcoord.x, heldBlockLightValue * 0.0625 + 0.03125);

	vec3 vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	#ifdef IDLE_HANDS
		if (heldItemId != 359 && heldItemId2 != 359) { //no hand sway when holding a map.
			vPosView.xy += sin(frameTimeCounter * vec2(1.6, 1.2)) * (sign(gl_ModelViewMatrix[3][0] + 0.3125) * 0.015625);
		}
	#endif
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);

	normal = normalize(gl_Normal) * 0.5 + 0.5;
	tint = gl_Color;
	tint.rgb *= min(normalize(gl_NormalMatrix * gl_Normal).y * 0.375 + 0.625 + heldBlockLightValue / 30.0, 1.25);

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif

	int heldItem = gl_ModelViewMatrix[3][0] > -0.3125 ? heldItemId : heldItemId2;
	if (heldItem == 95 || heldItem == 160) mcentity = 2.1; //stained glass
	else if (heldItem == 79) mcentity = 4.1; //ice
	else mcentity = 0.0;
}