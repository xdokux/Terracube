#version 120

#include "lib/defines.glsl"

uniform float frameTimeCounter;
uniform int heldItemId;
uniform int heldItemId2;
uniform mat4 gbufferModelViewInverse;
uniform vec3 actualCameraPosition;

varying vec2 texcoord;
#ifdef RAINBOW_ENCHANTMENTS
	varying vec3 rainbowPos;
#endif
varying vec3 vPosView;
varying vec4 tint;

void main() {
	vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;

	if (gl_ProjectionMatrix[2][2] > -0.5) {
		#ifdef IDLE_HANDS
			if (heldItemId != 359 && heldItemId2 != 359) { //no hand sway when holding a map.
				vPosView.xy += sin(frameTimeCounter * vec2(1.6, 1.2)) * (sign(gl_ModelViewMatrix[3][0] + 0.3125) * 0.015625);
			}
		#endif
		#ifdef RAINBOW_ENCHANTMENTS
			rainbowPos = vPosView * 2.0;
		#endif
	}
	#ifdef RAINBOW_ENCHANTMENTS
		else {
			rainbowPos = mat3(gbufferModelViewInverse) * vPosView + actualCameraPosition + vec3(0.5); //center of noisetex pixels should align to the edges of blocks.
		}
	#endif

	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	tint  =  gl_Color;
}