#version 120

#include "lib/defines.glsl"

uniform float frameTimeCounter;
uniform float wetness;
uniform sampler2D noisetex;
uniform sampler2D texture;

varying float ao;
varying float isDirt;
varying float isLava;
varying vec2 lmcoord;
varying vec2 randCoord;
varying vec2 texcoord;
varying vec4 tint;

#include "/lib/noiseres.glsl"

#ifdef LAVA_PATCHES
	float noiseMap(vec2 coord) {
		coord *= invNoiseRes;
		float noise = 0.0;
		noise += texture2D(noisetex, coord * 0.03125).r;
		noise += texture2D(noisetex, coord * 0.0625 ).r * 0.4;
		noise += texture2D(noisetex, coord * 0.125  ).r * 0.16;
		return noise;
	}
#endif

#ifdef WET_DIRT
	bool testDirt(vec3 color) {
		float hueIsh = (color.g - color.b) / (color.r - color.b);
		float saturationIsh = color.b / color.r;
		return hueIsh < saturationIsh || saturationIsh >= 0.99;
	}
#endif

void main() {
	vec4 color = texture2D(texture, texcoord);

	#ifdef GRASS_AO
		if (ao < 0.999) color.rgb *= sqrt(ao) * 0.5 + 0.5;
	#endif

	#ifdef LAVA_PATCHES
		if (isLava > 0.9 && color.r > 0.625) { //ignore non-lava part of magma blocks
			color.rgb += cos(
				noiseMap(randCoord) * 12.5
				+ frameTimeCounter * 0.5
			)
			* 0.125;
		}
	#endif

	#ifdef WET_DIRT
		if (wetness > 0.001 && isDirt > 0.5 && testDirt(color.rgb)) {
			float amt = min(wetness * lmcoord.y * lmcoord.y * 1.5, 1.0);
			float average = color.r + color.g + color.g;
			color.rgb = mix(color.rgb, color.rgb * 0.875 - average * 0.125, amt);
			//color.rgb = vec3(1.0, 0.0, 0.0);
		}
	#endif

	color *= tint;

/* DRAWBUFFERS:04 */
	gl_FragData[0] = color; //gcolor
	gl_FragData[1] = vec4(lmcoord, 1.0, color.a); //gaux1
}