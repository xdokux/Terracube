#version 120

#include "lib/defines.glsl"

uniform float blindness;
uniform float darknessLightFactor;
uniform float day;
uniform float fov;
uniform float night;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float rainStrength;
uniform float screenBrightness;
uniform float wetness;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
uniform sampler2D lightmap;
uniform sampler2D texture;
uniform vec3 actualCameraPosition;
#ifdef IS_IRIS
	uniform vec3 eyePosition;
#else
	vec3 eyePosition = actualCameraPosition;
#endif
uniform vec3 fogColor;

varying float id; //ID data of block currently being rendered.
varying vec2 lmcoord;
varying vec2 texcoord;
varying vec3 normal;
varying vec3 shadowColor; //Color of shadows. Sky-colored, to simulate indirect lighting.
varying vec3 skyLightColor; //Color of sky light. Is usually white during the day, and very dark blue at night.
varying vec4 tint;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

#include "lib/magicNumbers.glsl"

struct Position {
	//hackily set to actualCameraPosition + vec3(0.0, 1.0, 0.0).
	//this member is only used by calcMainLightColor() for held lights,
	//and all that matters for that is the distance between this and eyePosition.
	vec3 world;
};

#include "/lib/math.glsl"

#include "lib/calcMainLightColor.glsl"

void main() {
	float realId = id;
	vec4 color = texture2D(texture, texcoord) * tint;

	float skylight = lmcoord.y;
	float blocklight = lmcoord.x;
	float heldlight = 0.0;

	#ifdef BRIGHT_WATER
		if (isEyeInWater == 1) skylight = skylight * 0.5 + 0.5;
	#endif

	#ifdef ALT_GLASS
		bool lightable = true;
	#endif

	if (abs(realId - 0.2) < 0.02) { //stained glass
		if (color.a > THRESHOLD_ALPHA) {
			color.a = 1.0; //1.0 - (1.0 - color.a) * 0.5; //make borders more opaque
			realId = 0.0;
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

			color.rgb *= calcMainLightColor(blocklight, skylight, heldlight, pos);

			#include "lib/crossprocess.glsl"

			#include "lib/desaturate.glsl"

			if (blindness > 0) color.rgb *= 0.5 * blindness + (1.0 - blindness);

	#ifdef ALT_GLASS
		}
	#endif

/* DRAWBUFFERS:3562 */
	gl_FragData[0] = color; //gcolor
	gl_FragData[1] = vec4(lmcoord, realId, 1.0); //gaux2
	gl_FragData[2] = vec4(1.0, 0.0, 0.0, color.a); //gaux3
	gl_FragData[3] = vec4(normal, 1.0); //gnormal
}