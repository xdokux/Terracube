#version 120

#define ALT_GLASS //Uses alternate blending method for stained glass which looks more like real stained glass
#define BRIGHT_WATER //Overrides light levels under water to be higher
#define CLEAR_WATER //Overwrites water texture to be completely transparent
//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DYNAMIC_LIGHT_VIGNETTE 50 //Reduces the brightness of dynamic light around edges the of your screen [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
#define THRESHOLD_ALPHA 0.6 //Anything above this opacity counts as part of the border of stained glass, and will not apply blur/reflection effects [0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95]
//#define VANILLA_LIGHTMAP //Uses vanilla light colors instead of custom ones. Requires optifine 1.12.2 HD_U_D1 or later!

#define FOG_DISTANCE_MULTIPLIER_TF 0.25 //How far away fog starts to appear in the twilight forest [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
#define FOG_ENABLED_TF //Enables fog in the twilight forest
#define TF_HORIZON_HEIGHT 0.05 //How far above the horizon the fog color will be applied [0.001 0.002 0.003 0.004 0.005 0.0075 0.01 0.02 0.03 0.04 0.05 0.075 0.1 0.2 0.3 0.4 0.5 0.75 1.0]

uniform float blindness;
uniform float darknessLightFactor;
uniform float far;
uniform float fov;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform int isEyeInWater;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelView;
uniform sampler2D lightmap;
uniform sampler2D texture;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;

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
	vec3 viewNorm;
	vec3 player;
	vec3 world;
	float blockDist;
	float viewDist;
};

const vec3 blockLightColorNear   = vec3(1.0,   0.85,  0.7); //color of block lights when the player is near a light source.
const vec3 blockLightColorFar    = vec3(1.0,   0.5,   0.15); //color of block lights when the player is far away from a light source.
const vec3 nightVisionLightColor = vec3(0.375, 0.375, 0.5);

const vec3 blocklightVibrantColorFar  = vec3(1.4, 1.0, 0.8); //Vibrant color for block lights when standing far away from a light source.
const vec3 blocklightVibrantColorNear = vec3(1.2, 1.1, 1.0); //Vibrant color for block lights when standing near a light source.

const float lavaOverlayResolution                     = 24.0;

const vec3 skylightVibrantColor = vec3(1.1, 1.4, 1.2);

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).

float interpolateSmooth1(float x) { return x * x * (3.0 - 2.0 * x); }

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

vec3 calcMainLightColor(inout float blocklight, inout float skylight, inout float heldlight, inout Position pos) {
	#ifdef VANILLA_LIGHTMAP
		vec3 lightclr = texture2D(lightmap, vec2(blocklight, skylight)).rgb;
	#endif

	skylight *= skylight; // * (1.0 - rainStrength * 0.5);
	blocklight = square(max(blocklight - skylight * 0.5, 0.0));
	
	#ifndef VANILLA_LIGHTMAP
		vec3 lightclr = vec3(0.0);
		lightclr += mix(blockLightColorFar, blockLightColorNear, eyeBrightnessSmooth.x / 240.0) * blocklight; //blocklight
		lightclr += mix(skyColor, vec3(1.0), skylight) * skylight; //skylight
		lightclr += clamp(nightVision, 0.0, 1.0) * nightVisionLightColor;
		lightclr += clamp(screenBrightness, 0.0, 1.0) * 0.1;
	#endif

	#ifdef DYNAMIC_LIGHTS
		if (heldLightColor.a > 0.0) {
			float heldLightDist = pos.blockDist * fov / heldLightColor.a;
			if (heldLightDist < 1.0) {
				heldlight = (heldLightDist - log(heldLightDist) - 1.0) * heldLightColor.a / ((skylight + blocklight) * 64.0 + 32.0);
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

vec3 calcFogColor(vec3 pos) {
	return mix(skyColor, fogColor, fogify(max(dot(pos, gbufferModelView[1].xyz), 0.0), TF_HORIZON_HEIGHT));
}

void main() {
	int id = int(mcentity);
	vec4 color = texture2D(texture, texcoord) * tint;

	bool applyLighting = true;
	#ifdef FOG_ENABLED_TF
		bool applyFog = true;
	#endif

	if (id == 1) {
		#ifdef CLEAR_WATER
			color.a = 0.0;
			applyLighting = false;
		#endif
		#ifdef FOG_ENABLED_TF
			applyFog = false; //handled in composite
		#endif
	}
	else if (id == 2) {
		if (color.a > THRESHOLD_ALPHA) {
			color.a = 1.0; //make borders opaque
			id = 0;
		}
		#ifdef ALT_GLASS
			else {
				applyLighting = false;
				#ifdef FOG_ENABLED_TF
					applyFog = false;
				#endif
			}
		#endif
	}

	Position pos;
	pos.view = vPosView;
	pos.player = vPosPlayer;
	pos.world = pos.player + actualCameraPosition;
	pos.blockDist = length(pos.view);
	pos.viewDist = pos.blockDist / far;
	pos.viewNorm = pos.view / pos.blockDist;

	if (applyLighting) {
		float skylight = lmcoord.y;
		float blocklight = lmcoord.x;
		float heldlight = 0.0;

		#ifdef BRIGHT_WATER
			if (isEyeInWater == 1) skylight = skylight * 0.5 + 0.5;
		#endif

		color.rgb *= calcMainLightColor(blocklight, skylight, heldlight, pos);

		#ifdef CROSS_PROCESS
			vec3 blockCrossColor = mix(blocklightVibrantColorFar, blocklightVibrantColorNear, eyeBrightnessSmooth.x / 240.0); //cross processing color from block lights
			vec3 finalCrossColor = mix(mix(vec3(1.0), skylightVibrantColor, lmcoord.y), blockCrossColor, lmcoord.x); //final cross-processing color (blockCrossColor takes priority over skyCrossColor)
			//vec3(color.g + color.b, color.r + color.b, color.r + color.g)
			color.rgb = clamp(color.rgb * finalCrossColor - (color.grr + color.bbg) * 0.1, 0.0, 1.0);
		#endif

		if (blindness > 0.0) color.rgb *= interpolateSmooth1(max(1.0 - pos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);
	}

	#ifdef FOG_ENABLED_TF
		if (applyFog) {
			float fogAmount = pos.viewDist - 0.2;
			if (fogAmount > 0.0) {
				fogAmount = fogify(fogAmount * exp2(1.5 - pos.world.y * 0.015625), FOG_DISTANCE_MULTIPLIER_TF);
				color.rgb = mix(calcFogColor(pos.viewNorm) * min(max(lmcoord.y * 2.0, eyeBrightness.y / 120.0), 1.0) * (1.0 - blindness), color.rgb, fogAmount);
			}
		}
	#endif

/* DRAWBUFFERS:2563 */
	gl_FragData[0] = vec4(normal, 1.0); //gnormal
	gl_FragData[1] = vec4(lmcoord, id * 0.1, 1.0); //gaux2
	gl_FragData[2] = vec4(1.0, 0.0, 0.0, color.a); //gaux3
	gl_FragData[3] = color; //composite
}