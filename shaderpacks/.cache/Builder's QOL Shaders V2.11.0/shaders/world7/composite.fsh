#version 120

#define BRIGHT_WATER //Overrides light levels under water to be higher
//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DYNAMIC_LIGHT_VIGNETTE 50 //Reduces the brightness of dynamic light around edges the of your screen [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
#define UNDERWATER_FOG //Applies fog to water
//#define VANILLA_LIGHTMAP //Uses vanilla light colors instead of custom ones. Requires optifine 1.12.2 HD_U_D1 or later!

#define FOG_DISTANCE_MULTIPLIER_TF 0.25 //How far away fog starts to appear in the twilight forest [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
#define FOG_ENABLED_TF //Enables fog in the twilight forest
#define TF_AURORAS //Adds auroras to the sky in the twilight forest
#define TF_HORIZON_HEIGHT 0.05 //How far above the horizon the fog color will be applied [0.001 0.002 0.003 0.004 0.005 0.0075 0.01 0.02 0.03 0.04 0.05 0.075 0.1 0.2 0.3 0.4 0.5 0.75 1.0]
#define TF_SKY_FIX //Enable this if the sky looks wrong in the twilight forest

uniform float blindness;
uniform float darknessLightFactor;
uniform float far;
uniform float fov;
uniform float frameTimeCounter;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform int isEyeInWater;
bool inWater = isEyeInWater == 1; //quicker to type
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;

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

const int gcolorFormat    = RGBA16;
const int compositeFormat = RGBA16;
const int gaux3Format     = RGBA16;
const int gnormalFormat   = RGB16;
*/

const int noiseTextureResolution = 256;
const float invNoiseRes = 1.0 / float(noiseTextureResolution);

const vec3 blockLightColorNear   = vec3(1.0,   0.85,  0.7); //color of block lights when the player is near a light source.
const vec3 blockLightColorFar    = vec3(1.0,   0.5,   0.15); //color of block lights when the player is far away from a light source.
const vec3 nightVisionLightColor = vec3(0.375, 0.375, 0.5);

const vec3 blocklightVibrantColorFar  = vec3(1.4, 1.0, 0.8); //Vibrant color for block lights when standing far away from a light source.
const vec3 blocklightVibrantColorNear = vec3(1.2, 1.1, 1.0); //Vibrant color for block lights when standing near a light source.

const float lavaOverlayResolution                     = 24.0;

const vec3 skylightVibrantColor = vec3(1.1, 1.4, 1.2);

//Absorb colors are a bit odd in that higher numbers mean
//that the color gets *darker* more quickly with distance.
const vec3 waterAbsorbColor  = vec3(0.2,  0.05, 0.1);
const vec3 waterScatterColor = vec3(0.05, 0.4,  0.5);

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).

float interpolateSmooth1(float x) { return x * x * (3.0 - 2.0 * x); }

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

vec3 calcMainLightColor(inout float blocklight, inout float skylight, inout float heldlight, inout Position pos) {
	#ifdef VANILLA_LIGHTMAP
		vec3 lightclr = texture2D(gaux4, vec2(blocklight, skylight)).rgb;
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

vec3 calcUnderwaterFogColor(vec3 color, float dist, float brightness) {
	vec3 absorb = exp2(-dist * waterAbsorbColor);
	vec3 scatter = waterScatterColor * (1.0 - absorb) * brightness;
	return color * absorb + scatter;
}

vec3 calcUnderwaterFogColorInfinity(float brightness) {
	//simpler algorithm for the special case where distance = infinity (for looking at unobstructed sky while underwater)
	return waterScatterColor * brightness;
}

vec3 hue(float h) {
	h = fract(h) * 6.0;
	return clamp(
		vec3(
			abs(h - 3.0) - 1.0,
			2.0 - abs(h - 2.0),
			2.0 - abs(h - 4.0)
		),
		0.0,
		1.0
	);
}

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

	Position nearPos = posFromDepthtex(depthtex0);
	Position farPos = posFromDepthtex(depthtex1);

	vec3 color = texture2D(gcolor, tc).rgb;
	vec4 aux = texture2D(gaux1, tc);

	vec4 aux2 = texture2D(gaux2, tc);
	vec4 normal = texture2D(gnormal, tc);
	normal.xyz = normal.xyz * 2.0 - 1.0;
	bool water = int(aux2.b * 10.0 + 0.1) == 1; //only ID I'm actually checking for in this stage.

	float skylight = aux.g;
	float blocklight = aux.r;
	float heldlight = 0.0;

	float underwaterEyeBrightness = eyeBrightnessSmooth.y / 240.0;
	#ifdef BRIGHT_WATER
		underwaterEyeBrightness = underwaterEyeBrightness * 0.5 + 0.5;
	#endif

	if (!farPos.isSky) {
		#ifdef BRIGHT_WATER
			if      ( water && !inWater) skylight = max(skylight, aux2.g * 0.5);
			else if (!water &&  inWater) skylight = skylight * 0.5 + 0.5;
		#endif

		color *= calcMainLightColor(blocklight, skylight, heldlight, farPos);

		vec2 lmcoord = aux.rg;

		#ifdef CROSS_PROCESS
			vec3 blockCrossColor = mix(blocklightVibrantColorFar, blocklightVibrantColorNear, eyeBrightnessSmooth.x / 240.0); //cross processing color from block lights
			vec3 finalCrossColor = mix(mix(vec3(1.0), skylightVibrantColor, lmcoord.y), blockCrossColor, lmcoord.x); //final cross-processing color (blockCrossColor takes priority over skyCrossColor)
			//vec3(color.g + color.b, color.r + color.b, color.r + color.g)
			color.rgb = clamp(color.rgb * finalCrossColor - (color.grr + color.bbg) * 0.1, 0.0, 1.0);
		#endif

		//!water && !inWater = white fog in stage 1
		//!water &&  inWater = blue fog
		// water && !inWater = blue fog in stage 1 then white fog in stage 2
		// water &&  inWater = white fog in stage 1 then blue fog in stage 2

		//if water xor  inwater then blue fog
		//if water ==   inwater then white fog (stage 1)
		//if water and  inwater then blue fog
		//if water and !inwater then white fog (stage 2)

		#ifdef UNDERWATER_FOG
			if      (water && !inWater) color = calcUnderwaterFogColor(color, farPos.blockDist - nearPos.blockDist, aux2.g * aux2.g);
			else if (!water && inWater) color = calcUnderwaterFogColor(color, farPos.blockDist, underwaterEyeBrightness);
		#endif

		#ifdef FOG_ENABLED_TF
			if (water == inWater) {
				float fogAmount = (water ? farPos.viewDist - nearPos.viewDist : farPos.viewDist) - 0.2;
				if (fogAmount > 0.0) {
					fogAmount = fogify(fogAmount * exp2(1.5 - farPos.world.y * 0.015625), FOG_DISTANCE_MULTIPLIER_TF);
					float actualEyeBrightness = eyeBrightness.y / 240.0;
					#ifdef BRIGHT_WATER
						if (inWater) actualEyeBrightness = actualEyeBrightness * 0.5 + 0.5;
					#endif
					color = mix(calcFogColor(farPos.viewNorm) * min(max(aux.g, actualEyeBrightness) * 2.0, 1.0), color, fogAmount);
				}
			}
		#endif

		if (blindness > 0.0) color.rgb *= interpolateSmooth1(max(1.0 - farPos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);
	}
	else {
		if (water && !inWater) {
			color = calcUnderwaterFogColorInfinity(aux2.g * aux2.g);
		}
		else if (!water && inWater) {
			color = calcUnderwaterFogColorInfinity(underwaterEyeBrightness);
		}
		#ifdef TF_SKY_FIX
			else color = calcFogColor(farPos.viewNorm);
		#endif

		#ifdef TF_AURORAS
			if (!water || inWater) {
				float auroraBrightness = 1.0 - abs(farPos.playerNorm.y - 0.5) * 3.0;
				if (farPos.playerNorm.y > 0.0 && auroraBrightness > 0.0) {
					vec2 auroraStart = farPos.playerNorm.xz / farPos.playerNorm.y * invNoiseRes;
					vec2 auroraStep = auroraStart * -0.5;
					float dither = fract(dot(gl_FragCoord.xy, vec2(0.25, 0.5))) * 0.0625;
					float time = frameTimeCounter * invNoiseRes;
					vec3 auroraColor = vec3(0.0);
					for (int i = 0; i < 16; i++) {
						vec2 auroraPos = (i * 0.0625 + dither) * auroraStep + auroraStart;
						float noise = 1.0 - abs(texture2D(noisetex, vec2(auroraPos.x * 0.5 + (time * 0.03125), auroraPos.y * 2.0)).r * 10.0 - 5.0); //primary noise layer, defines the overall shape of auroras
						if (noise > 0.0) {
							noise *= square(texture2D(noisetex, vec2(auroraPos.x * 16.0, auroraPos.y * 16.0 + (time * 0.5))).r * 2.0 - 1.0); //secondary noise layer, adds detail to the auroras
							auroraColor += hue(texture2D(noisetex, auroraPos * 3.0 + (time * 0.1875)).r * 0.5 + 0.35) * noise * square(1.0 - abs(float(i) * 0.125 - 1.0)); //tertiary noise layer, defines the color of the auroras
						}
					}
					color += sqrt(auroraColor) * 0.75 * interpolateSmooth1(auroraBrightness);
				}
			}
		#endif

		color *= 1.0 - blindness;
	}

/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(color, texture2D(gaux3, texcoord).r); //gcolor, storing transparency data in alpha channel
}