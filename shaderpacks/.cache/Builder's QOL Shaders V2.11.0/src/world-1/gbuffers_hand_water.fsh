#version 120

#include "lib/defines.glsl"

uniform float blindness;
uniform float darknessLightFactor;
uniform float fov;
uniform float inSoulSandValley;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelViewInverse;
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
varying vec3 vPosPlayer;
varying vec3 vPosView;
varying vec4 tint;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

struct Position {
	vec3 view;
	vec3 player;
	vec3 world;
	float blockDist;
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
			color.a = 1.0; //make borders more opaque
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
			pos.view = vPosView;
			pos.player = vPosPlayer;
			pos.world = vPosPlayer + actualCameraPosition;
			pos.blockDist = 1.0; //spoof for hand.

			float blocklight = lmcoord.x;
			float heldlight = 0.0;

			color.rgb *= calcMainLightColor(blocklight, heldlight, pos);

			#include "lib/crossprocess.glsl"

			if (blindness > 0.0) color.rgb *= 0.5 * blindness + (1.0 - blindness);

	#ifdef ALT_GLASS
		}
	#endif

/* DRAWBUFFERS:3256 */
	gl_FragData[0] = color; //composite
	gl_FragData[1] = vec4(normal, 1.0); //gnormal
	gl_FragData[2] = vec4(lmcoord, id * 0.1, 1.0); //gaux2
	gl_FragData[3] = vec4(1.0, 0.0, 0.0, color.a); //gaux3
}