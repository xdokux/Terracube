#version 120

#include "lib/defines.glsl"

uniform float blindness;
uniform float darknessLightFactor;
uniform float fov;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform sampler2D lightmap;
uniform sampler2D texture;
uniform vec3 actualCameraPosition;
#ifdef IS_IRIS
	uniform vec3 eyePosition;
#else
	vec3 eyePosition = actualCameraPosition;
#endif

varying float mcentity; //ID data of block currently being rendered.
varying vec2 lmcoord;
varying vec2 texcoord;
varying vec3 normal;
varying vec4 tint;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

struct Position {
	vec3 world; //spoofed for held lights.
};

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "lib/calcMainLightColor.glsl"

void main() {
	vec4 color = texture2D(texture, texcoord) * tint;

	int id = int(mcentity);

	#ifdef ALT_GLASS
		bool lightable = true;
	#endif

	if (id == 2) { //stained glass
		if (color.a > THRESHOLD_ALPHA) {
			color.a = 1.0;//1.0 - (1.0 - color.a) * 0.5; //make borders more opaque
			id = 0;
		}
		#ifdef ALT_GLASS
			else lightable = false; //don't apply lighting effects to the center of glass when ALT_GLASS is enabled
		#endif
	}

	#ifdef ALT_GLASS
		if (lightable) {
	#endif
			Position pos;
			pos.world = actualCameraPosition + vec3(0.0, 1.0, 0.0);
			float blocklight = lmcoord.x;
			float heldlight = 0.0;

			color.rgb *= calcMainLightColor(blocklight, heldlight, pos);

			#include "lib/crossprocess.glsl"

			#include "lib/desaturate.glsl"

			color.rgb *= 0.5 * blindness + (1.0 - blindness);

	#ifdef ALT_GLASS
		}
	#endif

/* DRAWBUFFERS:3562 */
	gl_FragData[0] = color; //gcolor
	gl_FragData[1] = vec4(lmcoord, id * 0.1, 1.0); //gaux2
	gl_FragData[2] = vec4(1.0, 0.0, 0.0, color.a); //gaux3
	gl_FragData[3] = vec4(normal, 1.0); //gnormal
}