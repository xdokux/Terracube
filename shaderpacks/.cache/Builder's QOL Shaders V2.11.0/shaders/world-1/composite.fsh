#version 120

//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DYNAMIC_LIGHT_VIGNETTE 50 //Reduces the brightness of dynamic light around edges the of your screen [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
//#define VANILLA_LIGHTMAP //Uses vanilla light colors instead of custom ones. Requires optifine 1.12.2 HD_U_D1 or later!

#define FOG_DENSITY_MULTIPLIER_NETHER 1.0 //How much overall fog there is in the nether [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
#define FOG_ENABLED_NETHER //Enables fog in the nether
#define NETHER_LAVA_LEVEL 32.0 //Y level at which lava waves happen. Also controls some soul fire integration logic. [0.0 8.0 16.0 24.0 32.0 40.0 48.0 56.0 64.0 72.0 80.0 88.0 96.0 104.0 112.0 120.0 128.0 136.0 144.0 152.0 160.0 168.0 176.0 184.0 192.0 200.0 208.0 216.0 224.0 232.0 240.0 248.0 256.0]
#define SOUL_FIRE_INTEGRATION //When enabled, block light will be tinted blue in soul sand valleys
#define SOUL_LAVA //When enabled, lava and magma blocks will be blue tinted in soul sand valleys

uniform float blindness;
uniform float darknessLightFactor;
uniform float far;
uniform float fov;
uniform float frameTimeCounter;
uniform float inSoulSandValley;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform int bedrockLevel = 0;
uniform int logicalHeightLimit = 128;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D depthtex1;
uniform sampler2D gaux1;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D gcolor;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
#ifdef IS_IRIS
	uniform vec3 eyePosition;
#else
	vec3 eyePosition = actualCameraPosition;
#endif
uniform vec3 fogColor;

varying vec2 texcoord;
varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.

struct Position {
	bool isSky;
	vec3 view;
	vec3 viewNorm;
	vec3 player;
	vec3 playerNorm;
	vec3 world;
	float blockDist; //distance measured in blocks
	float viewDist; //blockDist / far
};

/*
because this has to be defined in the .fsh stage in order for optifine to recognize it:
uniform float centerDepthSmooth;

const float eyeBrightnessHalflife = 20.0;
const float centerDepthHalflife   =  1.0; //Smaller number makes DOF update faster [0.0625 0.09375 0.125 0.1875 0.25 0.375 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0 12.0 16.0]

const int gaux3Format     = RGBA16;
const int gcolorFormat    = RGBA16;
const int compositeFormat = RGBA16;
const int gnormalFormat   = RGB16;
*/

const int noiseTextureResolution = 256;
const float invNoiseRes = 1.0 / float(noiseTextureResolution);

const vec3 blockLightColorNear   = vec3(1.0,   0.85,  0.7); //color of block lights when the player is near a light source.
const vec3 blockLightColorFar    = vec3(1.0,   0.5,   0.15); //color of block lights when the player is far away from a light source.
const vec3 nightVisionLightColor = vec3(0.375, 0.375, 0.5);

const vec3 blocklightVibrantColorFar  = vec3(1.4, 1.0, 0.8); //Vibrant color for block lights when standing far away from a light source.
const vec3 blocklightVibrantColorNear = vec3(1.2, 1.1, 1.0); //Vibrant color for block lights when standing near a light source.
const float vibrantSaturation         = 0.1; //Higher numbers mean more saturation when vibrant colors are enabled.

const float lavaOverlayResolution                     = 24.0;

const vec3 blockLightColorNearInSoulSandValleys = vec3(0.8,     1.1,     1.4); //color of block lights in soul sand valleys when the player is near a light source.
const vec3 blockLightColorFarInSoulSandValleys  = vec3(0.25,    0.75,    1.5); //color of block lights in soul sand valleys when the player is far away from a light source.
const vec3 ambientLightColorInSoulSandValleys   = vec3(0.03125, 0.125,   0.125);
const vec3 ambientLightColorInOtherBiomes       = vec3(0.125,   0.03125, 0.03125);

const vec3 blockVibrantColorNearInSoulSandValleys = vec3(1.0,  1.1, 1.2); //vibrant color for block lights in soul sand valleys when the player is near a light source.
const vec3 blockVibrantColorFarInSoulSandValleys  = vec3(0.8,  1.0, 1.4); //vibrant color for block lights in soul sand valleys when the player is far away from a light source.
const vec3 ambientVibrantColorInSoulSandValleys   = vec3(0.75, 1.0, 1.5);
const vec3 ambientVibrantColorInOtherBiomes       = vec3(1.5,  1.0, 0.75);

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).

float interpolateSmooth1(float x) { return x * x * (3.0 - 2.0 * x); }

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

vec3 calcMainLightColor(inout float blocklight, inout float heldlight, inout Position pos) {
	#ifdef VANILLA_LIGHTMAP
		vec3 lightclr = texture2D(gaux4, vec2(blocklight, 0.98675)).rgb; //31/32 is the maximum light level in vanilla
	#endif

	blocklight *= blocklight;

	#ifndef VANILLA_LIGHTMAP
		vec3 lightclr = vec3(0.0);
		/*
		#ifdef SOUL_FIRE_INTEGRATION
		#endif
		*/
		#if defined(SOUL_FIRE_INTEGRATION) && MC_VERSION >= 11600
			#ifdef SOUL_LAVA
				float soul = inSoulSandValley;
			#else
				float soul = smoothstep(NETHER_LAVA_LEVEL, NETHER_LAVA_LEVEL + 16.0, pos.world.y) * inSoulSandValley;
			#endif
			lightclr += mix(
				mix(blockLightColorFar, blockLightColorFarInSoulSandValleys, soul),
				mix(blockLightColorNear, blockLightColorNearInSoulSandValleys, soul),
				eyeBrightnessSmooth.x / 240.0
			) * blocklight; //blocklight
			lightclr += mix(ambientLightColorInOtherBiomes, ambientLightColorInSoulSandValleys, soul); //ambient light
		#else
			lightclr += mix(blockLightColorFar, blockLightColorNear, eyeBrightnessSmooth.x / 240.0) * blocklight;
			lightclr += ambientLightColorInOtherBiomes;
		#endif
		lightclr += clamp(nightVision, 0.0, 1.0) * nightVisionLightColor;
		lightclr += clamp(screenBrightness, 0.0, 1.0) * 0.1;
	#endif

	#ifdef DYNAMIC_LIGHTS
		if (heldLightColor.a > 0.0) {
			float heldLightDist = distance(pos.world, eyePosition) * fov / heldLightColor.a;
			if (heldLightDist < 1.0) {
				heldlight = (heldLightDist - log(heldLightDist) - 1.0) * heldLightColor.a / (blocklight * 64.0 + 32.0);
				/*
				#ifdef DYNAMIC_LIGHT_VIGNETTE
				#endif
				*/
				#if DYNAMIC_LIGHT_VIGNETTE != 0
					vec2 screenPos = gl_FragCoord.xy * vec2(pixelSizeX, pixelSizeY); //0 to 1 range
					screenPos = screenPos * 2.0 - 1.0; //-1 to +1 range
					screenPos = 1.0 - screenPos * screenPos;
					float multiplier = screenPos.x * screenPos.y;
					multiplier = mix(1.0, multiplier, DYNAMIC_LIGHT_VIGNETTE / 100.0);
					heldlight *= multiplier;
				#endif
				lightclr += heldLightColor.rgb * heldlight;
			}
		}
	#endif

	return max(lightclr - square(darknessLightFactor), vec3(0.0));
}

#ifdef FOG_ENABLED_NETHER
	vec3 calcFogColor(vec3 playerPos) {
		vec3 fogclr = fogColor * (1.0 - nightVision * 0.5);
		float oldBrightness = dot(fogclr, vec3(0.33333333)) + 0.01;
		float newBrightness = oldBrightness * 0.25 / (oldBrightness + 0.25);
		fogclr *= newBrightness / oldBrightness;
		float n = square(texture2D(noisetex, frameTimeCounter * vec2(0.21562, 0.19361) * invNoiseRes).r) - 0.1;
		if (n > 0.0) {
			vec3 brightFog = vec3(
				fogclr.r * (n + 1.0),
				mix(fogclr.g, max(fogclr.r, fogclr.b * 2.0), n),
				fogclr.b
			);
			return mix(fogclr, brightFog, fogify(playerPos.y, 0.125));
		}
		else {
			return fogclr;
		}
	}
#endif

Position posFromDepthtex(sampler2D depthtex) {
	Position pos;
	float depth = texture2D(depthtex, texcoord).r;
	pos.isSky = depth == 1.0;
	vec3 screen = vec3(texcoord, depth);
	vec4 tmp = gbufferProjectionInverse * vec4(screen * 2.0 - 1.0, 1.0);
	pos.view = tmp.xyz / tmp.w;
	pos.player = mat3(gbufferModelViewInverse) * pos.view;
	pos.world = pos.player + actualCameraPosition;
	pos.blockDist = length(pos.view);
	pos.viewDist = pos.blockDist / far;
	pos.viewNorm = pos.view / pos.blockDist;
	pos.playerNorm = pos.player / pos.blockDist;
	return pos;
}

void main() {
	vec2 tc = texcoord;

	//position of opaque geometry.
	//must be named "pos" for cross processing.
	Position pos = posFromDepthtex(depthtex1);

	vec3 color = texture2D(gcolor, tc).rgb;

	#ifdef FOG_ENABLED_NETHER
		vec3 fogclr = calcFogColor(pos.playerNorm);
	#else
		vec3 fogclr = fogColor;
	#endif

	if (pos.isSky) {
		color = fogclr * (1.0 - blindness);
	}
	else {
		vec4 aux = texture2D(gaux1, tc);
		float blocklight = aux.r;
		float heldlight = 0.0;

		color *= calcMainLightColor(blocklight, heldlight, pos);

		vec2 lmcoord = aux.rg;

		#ifdef CROSS_PROCESS
			/*
			#ifdef SOUL_FIRE_INTEGRATION
			#endif
			*/
			#if defined(SOUL_FIRE_INTEGRATION) && MC_VERSION >= 11600
				#ifdef SOUL_LAVA
					float soul = inSoulSandValley;
				#else
					float soul = smoothstep(NETHER_LAVA_LEVEL, NETHER_LAVA_LEVEL + 16.0, pos.world.y) * inSoulSandValley;
				#endif
				vec3 blockCrossColor = mix(
					mix(blocklightVibrantColorFar, blockVibrantColorFarInSoulSandValleys, soul),
					mix(blocklightVibrantColorNear, blockVibrantColorNearInSoulSandValleys, soul),
					eyeBrightnessSmooth.x / 240.0
				);
				vec3 ambientCrossColor = mix(ambientVibrantColorInOtherBiomes, ambientVibrantColorInSoulSandValleys, soul);
				vec3 crossProcessColor = mix(ambientCrossColor, blockCrossColor, lmcoord.x); //final cross-processing color
			#else
				vec3 blockCrossColor = mix(blocklightVibrantColorFar, blocklightVibrantColorNear, eyeBrightnessSmooth.x / 240.0);
				vec3 crossProcessColor = mix(ambientVibrantColorInOtherBiomes, blockCrossColor, lmcoord.x); //final cross-processing color
			#endif
			color.rgb = clamp(color.rgb * crossProcessColor - (color.grr + color.bbg) * vibrantSaturation, 0.0, 1.0);
		#endif

		#ifdef FOG_ENABLED_NETHER
			color = mix(
				fogclr,
				color,
				exp2(
					pos.viewDist
					* exp2(
						abs(pos.world.y - (bedrockLevel + logicalHeightLimit))
						* (-4.0 / logicalHeightLimit)
						+ 4.0
					)
					* -FOG_DENSITY_MULTIPLIER_NETHER
				)
			);
		#endif

		if (blindness > 0.0) color *= interpolateSmooth1(max(1.0 - pos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);
	}

/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(color, texture2D(gaux3, texcoord).r); //gcolor
}