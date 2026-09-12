#version 120

//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DYNAMIC_LIGHT_FLICKER 8 //How much certain dynamic lights (like torches) will flicker [0 1 2 3 4 5 6 8 12 16 24 32 48 64]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]

#define HARDCORE_DARKNESS 0 //0 (Off): Normal visibility at night. 1 (On): Complete darkness at night. 2 (Moon phase) Nighttime brightness is determined by the current phase of the moon. [0 1 2]

uniform float adjustedTime;
uniform float day;
uniform float frameTimeCounter;
uniform float phase;
uniform float rainStrength;
uniform float sunset;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform sampler2D noisetex;
uniform vec3 fogColor;
uniform vec3 skyColor;

varying vec2 texcoord;
varying vec3 shadowColor; //Color of shadows. Sky-colored, to simulate indirect lighting.
varying vec3 skyLightColor; //Color of sky light. Is usually white during the day, and very dark blue at night.
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
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif

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