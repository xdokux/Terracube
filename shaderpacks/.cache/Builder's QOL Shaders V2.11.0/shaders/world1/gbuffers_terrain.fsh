#version 120

#define GRASS_AO //Adds ambient occlusion to tallgrass/flowers/etc... Works best with "Remove Y Offset" enabled.
#define LAVA_PATCHES //Randomizes lava brightness, similar to grass patches

uniform float frameTimeCounter;
uniform sampler2D noisetex;
uniform sampler2D texture;

varying float ao;
varying float isLava;
varying vec2 lmcoord;
varying vec2 randCoord;
varying vec2 texcoord;
varying vec4 tint;

const int noiseTextureResolution = 256;
const float invNoiseRes = 1.0 / float(noiseTextureResolution);

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

	color *= tint;

/* DRAWBUFFERS:04 */
	gl_FragData[0] = color; //gcolor
	gl_FragData[1] = vec4(lmcoord, 1.0, 1.0); //gaux1
}