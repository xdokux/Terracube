#version 120

#define BLUR_ENABLED //Is blur enabled at all?
#define DOF_STRENGTH 0 //Blurs things that are at a different distance than whatever's in the center of your screen [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define DYNAMIC_LIGHT_FLICKER 8 //How much certain dynamic lights (like torches) will flicker [0 1 2 3 4 5 6 8 12 16 24 32 48 64]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings

#define EYE_ADJUST_NETHER_DARK 2.5 //Brightness multiplier for the whole screen when standing in darkness in the nether [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define EYE_ADJUST_NETHER_LIGHT 1.5 //Brightness multiplier for the whole screen when standing in bright light in the nether [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]

uniform float centerDepthSmooth;
uniform float frameTimeCounter;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D noisetex;

#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
	varying float dofDistance; //Un-projected centerDepthSmooth
#endif
varying float eyeAdjust; //How much brighter to make the world
varying vec2 texcoord;
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

const int noiseTextureResolution = 256;
const float invNoiseRes = 1.0 / float(noiseTextureResolution);

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

	eyeAdjust = mix(EYE_ADJUST_NETHER_DARK, EYE_ADJUST_NETHER_LIGHT, eyeBrightnessSmooth.x / 240.0);

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		vec4 v = gbufferProjectionInverse * vec4(0.0, 0.0, centerDepthSmooth * 2.0 - 1.0, 1.0);
		dofDistance = -v.z / v.w;
	#endif

	#ifdef DYNAMIC_LIGHTS
		heldLightColor = calcHeldLightColor();
	#endif
}