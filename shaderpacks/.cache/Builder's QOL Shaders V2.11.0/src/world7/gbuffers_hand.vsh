#version 120

#include "lib/defines.glsl"

uniform float frameTimeCounter;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform int heldItemId2;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 tint;

void main() {
	vec3 vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	#ifdef IDLE_HANDS
		if (heldItemId != 359 && heldItemId2 != 359) { //no hand sway when holding a map.
			vPosView.xy += sin(frameTimeCounter * vec2(1.6, 1.2)) * (sign(gl_ModelViewMatrix[3][0] + 0.3125) * 0.015625);
		}
	#endif
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	lmcoord.x = max(lmcoord.x, heldBlockLightValue * 0.0625 + 0.03125);

	tint = gl_Color;
}