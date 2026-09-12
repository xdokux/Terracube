#version 120

#include "lib/defines.glsl"

uniform float adjustedTime;
uniform float day;
uniform float night;
uniform float nightVision;
uniform float phase;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float rainStrength;
uniform float sunset;
uniform float wetness;
uniform int bedrockLevel = 0;
uniform int heightLimit = 384;
uniform int worldDay;
uniform int worldTime;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
#ifndef SUN_POSITION_FIX
uniform vec3 sunPosNorm;
#endif

#ifdef SUN_POSITION_FIX
	varying vec3 sunPosNorm;
#endif
varying vec4 starData; //rgb = star color, a = flag for weather or not this pixel is a star.

struct Position {
	vec3 viewNorm;
	vec3 playerNorm;
	float sunDot;
	//float upDot is just playerNorm.y
	float spaceFactor;
};

const float sunPathRotation = 30.0; //Angle that the sun/moon rotate at [-45.0 -40.0 -35.0 -30.0 -25.0 -20.0 -15.0 -10.0 -5.0 0.0 5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0]

#include "/lib/noiseres.glsl"

#if defined(FANCY_STARS) || defined(GALAXIES)
	const mat2 starRotation = mat2(
		cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994),
		sin(sunPathRotation * 0.01745329251994),  cos(sunPathRotation * 0.01745329251994)
	);
#endif

#include "lib/magicNumbers.glsl"

#include "/lib/math.glsl"

#include "/lib/hue.glsl"

#include "lib/drawStars.glsl"

#include "lib/calcSkyColorFull.glsl"

//checks a few conditions before actually calculating the sky color.
vec3 checkSkyColor(inout Position pos) {
	if (starData.a > 0.5) {
		#ifdef FANCY_STARS
			return vec3(0.0);
		#else
			#ifdef INFINITE_OCEANS
				return starData.rgb * (1.0 - fogify(pos.playerNorm.y * pos.spaceFactor, 0.25)); //apply fog to stars near the horizon
			#else
				return starData.rgb;
			#endif
		#endif
	}

	return calcSkyColor(pos);
}

void main() {
	Position pos;
	vec2 tc = gl_FragCoord.xy * vec2(pixelSizeX, pixelSizeY);
	vec4 tmp = gbufferProjectionInverse * vec4(tc * 2.0 - 1.0, 1.0, 1.0);
	pos.viewNorm = normalize(tmp.xyz);
	pos.playerNorm = mat3(gbufferModelViewInverse) * pos.viewNorm;
	pos.sunDot = dot(pos.viewNorm, sunPosNorm);
	pos.spaceFactor = square(max(actualCameraPosition.y, (bedrockLevel + heightLimit)) * (1.0 / heightLimit) + 1.0);

	vec3 color = checkSkyColor(pos);

/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(color, 1.0); //gcolor
}