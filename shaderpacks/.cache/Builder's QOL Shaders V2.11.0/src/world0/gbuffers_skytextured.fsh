#version 120

#include "lib/defines.glsl"

uniform float pixelSizeX;
uniform float pixelSizeY;
uniform ivec4 blendFunc;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D texture;
uniform vec3 actualCameraPosition;
uniform vec3 upPosNorm;

varying vec2 texcoord;
varying vec4 tint;

#include "/lib/math.glsl"

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