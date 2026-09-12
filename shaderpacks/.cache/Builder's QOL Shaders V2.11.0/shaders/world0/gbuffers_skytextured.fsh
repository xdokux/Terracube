#version 120

//#define CUSTOM_SKY_FIX //Disables sun fadeout near the horizon when infinite oceans are enabled. Enable this if your resource pack's custom skys turn black near the horizon.
#define INFINITE_OCEANS //Simulates water out to the horizon instead of just your render distance.

uniform float pixelSizeX;
uniform float pixelSizeY;
uniform ivec4 blendFunc;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D texture;
uniform vec3 actualCameraPosition;
uniform vec3 upPosNorm;

varying vec2 texcoord;
varying vec4 tint;

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

/*
//required for optifine's option parsing logic.
#ifdef CUSTOM_SKY_FIX
#endif
*/

void main() {
	vec4 color = texture2D(texture, texcoord) * tint;

	//check for additive blending or an old optifine version which doesn't have the blendFunc uniform.
	if (blendFunc.xy == ivec2(770, 1) || blendFunc.xy == ivec2(0, 0)) {
		//fix alphaTestRef patch on 1.17+ causing the sun/moon to disappear
		//abruptly during the transition from clear weather to rain.
		color.rgb *= color.a;
		color.a = 1.0;

		#if defined(INFINITE_OCEANS) && !defined(CUSTOM_SKY_FIX)
			vec2 tc = gl_FragCoord.xy * vec2(pixelSizeX, pixelSizeY);
			vec4 tmp = gbufferProjectionInverse * vec4(tc * 2.0 - 1.0, 1.0, 1.0);
			vec3 viewPosNorm = normalize(tmp.xyz);
			float upDot = dot(viewPosNorm, upPosNorm) * square(max(actualCameraPosition.y, 256.0) / 256.0 + 1.0) * 0.5;
			color.rgb *= 1.0 - fogify(max(upDot, 0.0), 0.0625);
		#endif
	}

/* DRAWBUFFERS:0 */
	gl_FragData[0] = color; //gcolor
}