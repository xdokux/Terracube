#version 120

#define RAINBOW_ENCHANTMENTS //If enabled, the enchantment glint will be rainbow instead of the default purple color

uniform float blindness;
uniform float frameTimeCounter;
uniform sampler2D noisetex;
uniform sampler2D texture;

varying vec2 texcoord;
varying vec3 vPosView;
#ifdef RAINBOW_ENCHANTMENTS
	varying vec3 rainbowPos;
#endif
varying vec4 tint;

const int noiseTextureResolution = 256;
const float invNoiseRes = 1.0 / float(noiseTextureResolution);

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).

float interpolateSmooth1(float x) { return x * x * (3.0 - 2.0 * x); }

vec3 hue(float h) {
	h = fract(h) * 6.0;
	return clamp(
		vec3(
			abs(h - 3.0) - 1.0,
			2.0 - abs(h - 2.0),
			2.0 - abs(h - 4.0)
		),
		0.0,
		1.0
	);
}

void main() {
	vec4 color = texture2D(texture, texcoord);
	
	#ifdef RAINBOW_ENCHANTMENTS
		float noise = frameTimeCounter;
		noise += texture2D(noisetex, rainbowPos.xz * invNoiseRes).r;
		noise += texture2D(noisetex, rainbowPos.xy * invNoiseRes).r;
		noise += texture2D(noisetex, rainbowPos.yz * invNoiseRes).r;
		color.rgb = hue(noise) * square(max(max(color.r, color.g), color.b));
	#else
		color.rgb *= tint.rgb;
	#endif
	color.rgb *= tint.a;

	if (blindness > 0.0) color.rgb *= interpolateSmooth1(max(1.0 - length(vPosView) * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);

/* DRAWBUFFERS:04 */
	gl_FragData[0] = color; //gcolor
	gl_FragData[1] = vec4(0.5, 0.0, 1.0, 1.0); //gaux1 //increase brightness
}