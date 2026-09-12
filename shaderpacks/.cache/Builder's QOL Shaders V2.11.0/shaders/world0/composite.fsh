#version 120

#define BRIGHT_WATER //Overrides light levels under water to be higher
//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DYNAMIC_LIGHT_VIGNETTE 50 //Reduces the brightness of dynamic light around edges the of your screen [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
#define UNDERWATER_FOG //Applies fog to water
//#define VANILLA_LIGHTMAP //Uses vanilla light colors instead of custom ones. Requires optifine 1.12.2 HD_U_D1 or later!

#define DESATURATE_NIGHT 0.50 //Amount to desaturate the world at night [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define DESATURATE_RAIN 0.50 //Amount to desaturate the world when raining [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define FOG_DENSITY_MULTIPLIER_OVERWORLD 1.00 //How much overall fog there is in the overworld. [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00 2.50 3.00 3.50 4.00 4.50 5.00 6.00 7.00 8.00 9.00 10.00]
#define FOG_ENABLED_OVERWORLD //Enables fog in the overworld. It is recommended to have this enabled if you also have infinite oceans enabled!
#define FOG_HEIGHT_MULTIPLIER_OVERWORLD 32.0 //Controls how much denser fog is at lower altitudes [16.0 24.0 32.0 48.0 64.0 96.0 128.0 192.0 256.0 384.0 512.0 768.0 1024.0]
#define INFINITE_OCEANS //Simulates water out to the horizon instead of just your render distance.
#define OVERWORLD_FOG_SATURATION_BOOST 1.25 //Makes the horizon blue-er [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50]
#define OVERWORLD_HORIZON_HEIGHT 0.2 //How far above the horizon the fog color will be applied [0.001 0.002 0.003 0.004 0.005 0.0075 0.01 0.02 0.03 0.04 0.05 0.075 0.1 0.2 0.3 0.4 0.5 0.75 1.0]
#define OVERWORLD_SKY_SATURATION_BOOST 1.50 //Makes the sky blue-er [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50]
#define RAINBOWS //If enabled, rainbows will appear when the weather changes from rainy to clear
#define SEA_LEVEL 63 //Sea level for infinite oceans. Change this if you use custom worldgen. [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256]

uniform float adjustedTime;
uniform float blindness;
uniform float darknessLightFactor;
uniform float day;
uniform float far;
uniform float fogEnd;
uniform float fov;
uniform float night;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float rainStrength;
uniform float screenBrightness;
uniform float sunset;
uniform float wetness;
uniform int isEyeInWater;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux3;
uniform sampler2D gaux4; //lightmap
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform vec3 actualCameraPosition;
#ifdef IS_IRIS
	uniform vec3 eyePosition;
#else
	vec3 eyePosition = actualCameraPosition;
#endif
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunPosNorm;
uniform vec3 upPosNorm;

varying vec2 texcoord;
varying vec3 shadowColor; //Color of shadows. Sky-colored, to simulate indirect lighting.
varying vec3 skyLightColor; //Color of sky light. Is usually white during the day, and very dark blue at night.
varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.

struct Position {
	bool isSky;
	vec3 view;
	vec3 viewNorm;
	vec3 player;
	vec3 world;
	float blockDist; //distance measured in blocks
	float viewDist; //blockDist / far
};

/*
because this has to be defined in the .fsh stage in order for optifine to recognize it:
uniform float centerDepthSmooth;

const float eyeBrightnessHalflife = 20.0;
const float wetnessHalflife = 250.0;
const float drynessHalflife = 60.0;
const float centerDepthHalflife   =  1.0; //Smaller number makes DOF update faster [0.0625 0.09375 0.125 0.1875 0.25 0.375 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0 12.0 16.0]

const int gcolorFormat = RGBA16;
const int compositeFormat = RGBA16;
const int gaux3Format = RGBA16;
const int gnormalFormat = RGB16;
*/

const float actualSeaLevel = SEA_LEVEL - 0.1111111111111111; //water source blocks are 8/9'ths of a block tall, so SEA_LEVEL - 1/9.

const vec3 blockLightColorNear   = vec3(1.0,   0.85,  0.7); //color of block lights when the player is near a light source.
const vec3 blockLightColorFar    = vec3(1.0,   0.5,   0.15); //color of block lights when the player is far away from a light source.
const vec3 nightVisionLightColor = vec3(0.375, 0.375, 0.5);

const vec3 blocklightVibrantColorFar  = vec3(1.4, 1.0, 0.8); //Vibrant color for block lights when standing far away from a light source.
const vec3 blocklightVibrantColorNear = vec3(1.2, 1.1, 1.0); //Vibrant color for block lights when standing near a light source.
const float vibrantSaturation         = 0.1; //Higher numbers mean more saturation when vibrant colors are enabled.

const float lavaOverlayResolution                     = 24.0;

#ifdef CROSS_PROCESS
	const vec3 nightSkyColor = vec3(0.02,  0.025, 0.05); //Added to sky color at night to avoid it being completely black
#else
	const vec3 nightSkyColor = vec3(0.025, 0.025, 0.05); //Added to sky color at night to avoid it being completely black
#endif

const vec3 sunsetColorForSky = vec3(7.2, 6.7, 6.2); //Subtract 6.0 from this to get the color of the horizon at sunset.

const float rainbowPosition =   0.25; //1.0 will be on top of the sun, 0.0 will be on top of the moon.
const float rainbowThinness = -24.0; //Positive numbers will make red be on the inside and blue on the outside.

//Absorb colors are a bit odd in that higher numbers mean
//that the color gets *darker* more quickly with distance.
const vec3 waterAbsorbColorWhenSunny   = vec3(0.2,   0.05,   0.1);
const vec3 waterAbsorbColorWhenRaining = vec3(0.125, 0.0625, 0.25);

const vec3 waterScatterColorWhenSunny   = vec3(0.05,    0.4, 0.5);
const vec3 waterScatterColorWhenRaining = vec3(0.09375, 0.1, 0.15);

const vec3 skylightVibrantColorDuringTheDay = vec3(1.4, 1.2, 1.1);
const vec3 skylightVibrantColorAtNight      = vec3(1.0, 1.1, 1.4);
const vec3 skylightVibrantColorWhenRaining  = vec3(1.0, 1.0, 1.0); //Overrides both day and night.

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).

float interpolateSmooth1(float x) { return x * x * (3.0 - 2.0 * x); }
vec3  interpolateSmooth3(vec3  v) { return v * v * (3.0 - 2.0 * v); }

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

vec3 calcMainLightColor(inout float blocklight, inout float skylight, inout float heldlight, inout Position pos) {
	#ifdef VANILLA_LIGHTMAP
		vec3 lightclr = texture2D(gaux4, vec2(blocklight, skylight)).rgb;
	#endif

	skylight *= skylight * (1.0 - rainStrength * 0.5);
	blocklight = square(max(blocklight - skylight * day * 0.5, 0.0));

	#ifndef VANILLA_LIGHTMAP
		vec3 lightclr = vec3(0.0);
		lightclr += mix(blockLightColorFar, blockLightColorNear, eyeBrightnessSmooth.x / 240.0) * blocklight; //blocklight
		lightclr += mix(shadowColor, skyLightColor, skylight) * skylight; //skylight
		lightclr += clamp(nightVision, 0.0, 1.0) * nightVisionLightColor;
		lightclr += clamp(screenBrightness, 0.0, 1.0) * 0.1;
	#endif

	#ifdef DYNAMIC_LIGHTS
		if (heldLightColor.a > 0.0) {
			float heldLightDist = distance(pos.world, eyePosition) * fov / heldLightColor.a;
			if (heldLightDist < 1.0) {
				heldlight = (heldLightDist - log(heldLightDist) - 1.0) * heldLightColor.a / ((skylight * day + blocklight) * 64.0 + 32.0);
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

float calcFogAmount(inout Position pos, in float fogDistance) {
	float fogDensity = exp2(
		(
			//equivalen to: (pos.world.y - SEA_LEVEL) * (-1.0 / FOG_HEIGHT_MULTIPLIER_OVERWORLD)
			pos.world.y
			* (-1.0 / FOG_HEIGHT_MULTIPLIER_OVERWORLD)
			+ (SEA_LEVEL / FOG_HEIGHT_MULTIPLIER_OVERWORLD)
		)
		* (1.0 - rainStrength)
		+ (rainStrength * 2.0)
	)
	* FOG_DENSITY_MULTIPLIER_OVERWORLD;
	return fogify(fogDistance * fogDensity, 1.0);
}

vec3 calcFogColor(vec3 viewPosNorm) {
	float upDot = dot(viewPosNorm, upPosNorm) * 2.0;
	float sunDot = dot(viewPosNorm, sunPosNorm) * 0.5 + 0.5;
	float rainCoefficient = max(rainStrength, wetness);
	vec3 color;
	vec3 skyclr = skyColor;
	skyclr.rg = mix(skyclr.bb, skyclr.rg, OVERWORLD_SKY_SATURATION_BOOST);
	skyclr = mix(skyclr, fogColor * 0.65, rainCoefficient);
	vec3 fogclr = fogColor;
	fogclr.rg = mix(fogclr.bb, fogclr.rg, OVERWORLD_FOG_SATURATION_BOOST);
	fogclr *= (1.0 - rainCoefficient * 0.25) * (1.0 - nightVision * night * 0.75);

	if (upDot > 0.0) color = skyclr + nightSkyColor * (1.0 - day) * (1.0 - rainStrength); //avoid pitch black sky at night
	else color = fogclr;

	if (sunset > 0.001 && rainCoefficient < 0.999) {
		vec3 sunsetColor = interpolateSmooth3(clamp(sunsetColorForSky - adjustedTime + upDot + sunDot * 0.2 * (1.0 - night), 0.0, 1.0)); //main sunset gradient
		sunsetColor = mix(fogclr, sunsetColor, (sunDot * 0.5 + 0.5) * sunset * (1.0 - rainCoefficient)); //fade in at sunset and out when not looking at the sun
		color = mix(color, sunsetColor, fogify(upDot, OVERWORLD_HORIZON_HEIGHT)); //mix with final color based on how close we are to the horizon
	}
	else if (upDot > 0.0) color = mix(color, fogclr, fogify(upDot, OVERWORLD_HORIZON_HEIGHT));

	#ifdef RAINBOWS
		float rainbowStrength = (wetness - rainStrength) * day * 0.25;
		float rainbowHue = (sunDot - rainbowPosition) * rainbowThinness;
		if (rainbowStrength > 0.01 && rainbowHue > 0.0 && rainbowHue < 1.0) {
			rainbowHue *= 6.0;
			color += clamp(vec3(1.5, 2.0, 1.5) - abs(rainbowHue - vec3(1.5, 3.0, 4.5)), 0.0, 1.0) * rainbowStrength;
			//color.r += clamp(1.5 - abs(rainbowHue - 1.5), 0.0, 1.0) * rainbowStrength;
			//color.g += clamp(2.0 - abs(rainbowHue - 3.0), 0.0, 1.0) * rainbowStrength;
			//color.b += clamp(1.5 - abs(rainbowHue - 4.5), 0.0, 1.0) * rainbowStrength;
		}
	#endif

	return color;
}

vec3 calcUnderwaterFogColor(vec3 color, float blockDist, float brightness) {
	float rainCoefficient = max(rainStrength, wetness);
	vec3 absorb = exp2(-blockDist * mix(waterAbsorbColorWhenSunny, waterAbsorbColorWhenRaining, rainCoefficient));
	vec3 scatter = mix(waterScatterColorWhenSunny, waterScatterColorWhenRaining, rainCoefficient) * (1.0 - absorb) * (brightness * day);
	return color * absorb + scatter;
}

//simpler algorithm for the special case where distance = infinity (for infinite oceans)
vec3 calcUnderwaterFogColorInfinity(float brightness) {
	return mix(waterScatterColorWhenSunny, waterScatterColorWhenRaining, max(rainStrength, wetness)) * (brightness * day);
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
	bool inWater = isEyeInWater == 1; //quicker to type.

	float underwaterEyeBrightness = eyeBrightnessSmooth.y / 240.0;
	#ifdef BRIGHT_WATER
		underwaterEyeBrightness = underwaterEyeBrightness * 0.5 + 0.5;
	#endif

	if (!farPos.isSky) {
		float skylight = aux.g;
		float blocklight = aux.r;
		float heldlight = 0.0;

		#ifdef BRIGHT_WATER
			if      ( water && !inWater) skylight = mix(skylight, skylight * 0.5 + 0.5, aux2.g); //max(skylight, aux2.g * 0.5);
			else if (!water &&  inWater) skylight = skylight * 0.5 + 0.5;
		#endif

		color *= calcMainLightColor(blocklight, skylight, heldlight, farPos);

		vec2 lmcoord = aux.rg;

		#ifdef CROSS_PROCESS
			vec3 skyCrossColor    = mix(mix(skylightVibrantColorDuringTheDay, skylightVibrantColorAtNight, night), skylightVibrantColorWhenRaining, wetness); //cross processing color from the sun
			vec3 blockCrossColor  = mix(blocklightVibrantColorFar, blocklightVibrantColorNear, eyeBrightnessSmooth.x / 240.0); //cross processing color from block lights
			vec3 finalCrossColor  = mix(mix(vec3(1.0), skyCrossColor, lmcoord.y), blockCrossColor, lmcoord.x); //final cross-processing color (blockCrossColor takes priority over skyCrossColor)
			color.rgb = clamp(color.rgb * finalCrossColor - (color.grr + color.bbg) * vibrantSaturation, 0.0, 1.0);
		#endif

		float desaturationAmount = mix(night * DESATURATE_NIGHT, 1.0, rainStrength * DESATURATE_RAIN);
		if (desaturationAmount > 0.001) {
			desaturationAmount *= 1.0 - max(blocklight, heldlight);
			float average = dot(color.rgb, vec3(0.25, 0.5, 0.25));
			color.rgb = mix(color.rgb, vec3(average), desaturationAmount);
		}

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

		#ifdef FOG_ENABLED_OVERWORLD
			if (water == inWater) {
				float fogDistance = (water ? farPos.blockDist - nearPos.blockDist : farPos.blockDist) / fogEnd;
				float actualEyeBrightness = eyeBrightness.y / 240.0;
				#ifdef BRIGHT_WATER
					if (inWater) actualEyeBrightness = actualEyeBrightness * 0.5 + 0.5;
				#endif
				color = mix(calcFogColor(farPos.viewNorm) * min(max(aux.g, actualEyeBrightness) * 2.0, 1.0), color, calcFogAmount(farPos, fogDistance));
			}
		#endif

		if (blindness > 0.0) color.rgb *= interpolateSmooth1(max(1.0 - farPos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);
	}
	else {
		if (nearPos.isSky) {
			#ifdef INFINITE_OCEANS
				if (actualCameraPosition.y > actualSeaLevel) {
					if (nearPos.player.y < 0.0) {
						aux2.g = 0.96875;
						aux2.b = 0.1; //water ID
						normal = vec4(0.0, 1.0, 0.0, 1.0);
						water = true;
					}
				}
				else if (inWater) {
					if (nearPos.player.y > 0.0) {
						aux2.g = 0.96875;
						aux2.b = 0.1; //water ID
						normal = vec4(0.0, -1.0, 0.0, 1.0);
						water = true;
					}
					#ifdef UNDERWATER_FOG
						else {
							color = calcUnderwaterFogColorInfinity(underwaterEyeBrightness);
						}
					#endif
				}
			#else
				#ifdef UNDERWATER_FOG
					if (inWater) {
						color = calcUnderwaterFogColorInfinity(underwaterEyeBrightness);
					}
				#endif
			#endif
		}
		if (water && !inWater) {
			color = calcUnderwaterFogColorInfinity(0.9384765625);
		}
		color *= 1.0 - blindness;
	}

/* DRAWBUFFERS:025 */
	gl_FragData[0] = vec4(color, texture2D(gaux3, texcoord).r); //gcolor, storing transparency data in alpha channel
	gl_FragData[1] = normal * 0.5 + 0.5; //gnormal
	gl_FragData[2] = aux2; //gaux2
}