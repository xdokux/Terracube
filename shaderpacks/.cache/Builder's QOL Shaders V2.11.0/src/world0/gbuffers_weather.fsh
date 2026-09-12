#version 120

#include "lib/defines.glsl"

uniform float night;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float rainStrength;
uniform float wetness;
uniform int bedrockLevel = 0;
uniform int heightLimit = 384;
uniform sampler2D depthtex0;
uniform sampler2D texture;
uniform vec3 fogColor;

#ifdef CLOUDS
	varying float worldHeight;
#endif
varying vec2 texcoord;
varying vec4 tint;

void main() {
	#ifdef CLOUDS
		if (worldHeight > bedrockLevel + heightLimit) discard; //don't draw rain above clouds.
	#endif

	vec4 color = texture2D(texture, texcoord) * tint;

	if (texture2D(depthtex0, gl_FragCoord.xy * vec2(pixelSizeX, pixelSizeY)).r == 1.0) {
		color.rgb = fogColor * (1.0 - max(rainStrength, wetness) * 0.5) * (1.0 - nightVision * night * 0.75);
	}
	color.a *= 2.0 - color.a;

/* DRAWBUFFERS:0 */
	gl_FragData[0] = color; //gcolor
}