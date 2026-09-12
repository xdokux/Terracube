#version 120

#include "lib/defines.glsl"

uniform float blindness;
uniform float frameTimeCounter;
uniform sampler2D noisetex;
uniform sampler2D texture;

varying vec2 texcoord;
#ifdef RAINBOW_ENCHANTMENTS
	varying vec3 rainbowPos;
#endif
varying vec3 vPosView;
varying vec4 tint;

#include "/lib/noiseres.glsl"

#include "/lib/math.glsl"

#include "/lib/hue.glsl"

void main() {
	vec4 color = texture2D(texture, texcoord);
	
	#include "/lib/rainbowEnchantments.glsl"

	if (blindness > 0.0) color.rgb *= interpolateSmooth1(max(1.0 - length(vPosView) * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);

/* DRAWBUFFERS:04 */
	gl_FragData[0] = color; //gcolor
	gl_FragData[1] = vec4(0.5, 0.0, 1.0, 1.0); //gaux1 //increase brightness
}