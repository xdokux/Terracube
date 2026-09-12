#version 120

//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DYNAMIC_LIGHT_FLICKER 8 //How much certain dynamic lights (like torches) will flicker [0 1 2 3 4 5 6 8 12 16 24 32 48 64]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
#define IDLE_HANDS //Makes your hands sway back and forth in 1st person, like they do in 3rd person

#define HARDCORE_DARKNESS 0 //0 (Off): Normal visibility at night. 1 (On): Complete darkness at night. 2 (Moon phase) Nighttime brightness is determined by the current phase of the moon. [0 1 2]
#define SHADE_STRENGTH 0.35 //How dark surfaces that are facing away from the sun are [0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.50]

uniform float adjustedTime;
uniform float day;
uniform float frameTimeCounter;
uniform float night;
uniform float phase;
uniform float rainStrength;
uniform float sunset;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform int heldItemId2;
uniform sampler2D noisetex;
uniform vec3 fogColor;
uniform vec3 skyColor;
		uniform vec3 sunPosNorm;

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

const int noiseTextureResolution = 256;
const float invNoiseRes = 1.0 / float(noiseTextureResolution);

const float lavaOverlayResolution                     = 24.0;

#ifdef CROSS_PROCESS
#else
#endif

const vec3 sunsetColorForSky = vec3(7.2, 6.7, 6.2); //Subtract 6.0 from this to get the color of the horizon at sunset.
//Roughly corresponds to the color a bit above the horizon at sunset,
//or the horizon itself a bit before sunset.
//usages include:
//	color of skylight at sunset
//	color of light applied to my fancy clouds
const vec3 sunsetColorForOtherThings = sunsetColorForSky + vec3(0.2, 0.2, 0.2);

const vec3 skylightColorDuringTheDay = vec3(1.0,  1.0, 1.0);
const vec3 skylightColorAtNight      = vec3(0.05, 0.1, 0.15); //If hardcore darkness is enabled, this will be 0 instead.

#ifdef DYNAMIC_LIGHTS
	float flicker() {
		/*
		#ifdef DYNAMIC_LIGHT_FLICKER
		#endif
		*/
		#if DYNAMIC_LIGHT_FLICKER != 0
			float n = texture2D(noisetex, frameTimeCounter * vec2(16.7825, 15.4192) * invNoiseRes).r - 0.5;
			return n * n * n * DYNAMIC_LIGHT_FLICKER;
		#else
			return 0.0;
		#endif
	}

	vec4 calcHeldLightColor() { //rgb = color, a = brightness
		if (heldBlockLightValue == 0) return vec4(0.0); //not holding a light source
		else if (heldItemId == 50   ) return vec4(1.0,  0.6,  0.3, heldBlockLightValue + flicker()); //regular torches/lanterns/campfires
		else if (heldItemId == 89   ) return vec4(1.0,  0.6,  0.1, heldBlockLightValue            ); //glowstone
		else if (heldItemId == 169  ) return vec4(0.6,  0.8,  0.6, heldBlockLightValue            ); //sea lanterns
		else if (heldItemId == 198  ) return vec4(0.75, 0.55, 0.8, heldBlockLightValue            ); //end rods
		else if (heldItemId == 76   ) return vec4(1.0,  0.3,  0.1, heldBlockLightValue + flicker()); //redstone torches
		else if (heldItemId == 91   ) return vec4(1.0,  0.5,  0.1, heldBlockLightValue + flicker()); //jack-o-lanterns
		else if (heldItemId == 138  ) return vec4(0.4,  0.6,  0.8, heldBlockLightValue            ); //beacons
		#if MC_VERSION >= 11600
		else if (heldItemId == 10001) return vec4(0.3,  0.6,  1.0, heldBlockLightValue + flicker()); //soul torches/lanterns/campfires.
		else if (heldItemId == 10002) return vec4(1.0,  0.5,  0.1, heldBlockLightValue            ); //shroomlight
		else if (heldItemId == 10004) return vec4(0.625 + sin(frameTimeCounter) * 0.125, 0.25, 1.0, heldBlockLightValue); //crying obsidian
		#endif
		#if MC_VERSION >= 11300
		else if (heldItemId == 10003) return vec4(0.9,  1.0,  0.5, heldBlockLightValue            ); //sea pickles
		#endif
		else                          return vec4(0.8,  0.65, 0.5, heldBlockLightValue            ); //everything else
	}
#endif

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	lmcoord.x = max(lmcoord.x, heldBlockLightValue * 0.0625 + 0.03125);

	vec3 vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	#ifdef IDLE_HANDS
		if (heldItemId != 359 && heldItemId2 != 359) { //no hand sway when holding a map.
			vPosView.xy += sin(frameTimeCounter * vec2(1.6, 1.2)) * (sign(gl_ModelViewMatrix[3][0] + 0.3125) * 0.015625);
		}
	#endif
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);

	tint = gl_Color;

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif

	int heldItem = gl_ModelViewMatrix[3][0] > -0.3125 ? heldItemId : heldItemId2;
	if (heldItem == 95 || heldItem == 160) id = 0.2; //stained glass
	else if (heldItem == 79) id = 0.4; //ice
	else id = 0.0;

	//note: apparently gl_Normal is NOT automaticaly normalized when rendering the hand.
	//this causes issues with reflections on held objects
	//as such, we need to normalize it manually.
	normal = normalize(gl_NormalMatrix * gl_Normal);
	float glmult = 0.0;
	if (night < 0.999) glmult += dot( sunPosNorm, normal) * (1.0 - night);
	if (night > 0.001) glmult += dot(-sunPosNorm, normal) * night;
	//glmult = glmult * 0.375 + 0.625; //0.25 - 1.0
	glmult = glmult * SHADE_STRENGTH + (1.0 - SHADE_STRENGTH);
	glmult = mix(glmult, 1.0, rainStrength * 0.5); //less shading during rain
	glmult = mix(1.0, glmult, lmcoord.y * 0.66666666 + 0.33333333); //0.5 - 1.0 in darkness
	glmult = mix(glmult, 1.0, lmcoord.x * lmcoord.x); //increase brightness when block light is high
	tint.rgb *= glmult;
	normal = normalize(gl_Normal) * 0.5 + 0.5;

	skyLightColor = skylightColorDuringTheDay * day;
	shadowColor = mix(skyColor, fogColor, rainStrength);

	if (sunset > 0.01) {
		vec3 sunsetColor = clamp(sunsetColorForOtherThings - adjustedTime, 0.0, 1.0); //color of sunset gradient at the horizon, and mix level
		if (rainStrength > 0.001) sunsetColor = mix(sunsetColor, fogColor * (1.0 - rainStrength * 0.5), rainStrength * 0.625); //reduce redness intensity when raining
		sunsetColor   *= sunset;
		skyLightColor += sunsetColor;
		shadowColor   += sunsetColor;
	}

	#if HARDCORE_DARKNESS == 0
		skyLightColor += skylightColorAtNight * (1.0 - day);
	#elif HARDCORE_DARKNESS == 1
		//skyLightColor += vec3(0.0);
	#elif HARDCORE_DARKNESS == 2
		skyLightColor += skylightColorAtNight * ((1.0 - day) * phase);
	#else
		#error HARDCORE_DARKNESS should be set to 0, 1, or 2.
	#endif
}