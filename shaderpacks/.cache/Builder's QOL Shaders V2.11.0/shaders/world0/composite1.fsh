#version 120

#define ALT_GLASS //Uses alternate blending method for stained glass which looks more like real stained glass
#define BLUR_ENABLED //Is blur enabled at all?
#define BRIGHT_WATER //Overrides light levels under water to be higher
#define CLOUDS //3D clouds (partially volumetric too). Mild performance impact!
//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DOF_STRENGTH 0 //Blurs things that are at a different distance than whatever's in the center of your screen [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define DYNAMIC_LIGHT_VIGNETTE 50 //Reduces the brightness of dynamic light around edges the of your screen [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define GLASS_BLUR 8 //Blurs things behind stained glass [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
#define ICE_BLUR 4 //Blurs things behind ice [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define ICE_NORMALS //Distorts things reflected by ice. Has no effect when reflections are disabled!
#define ICE_REFRACT //Distorts things behind ice
//#define OLD_CLOUDS //Makes fancy clouds more square-shaped
#define REFLECT //Reflects the sun/sky onto reflective surfaces. Does not add reflections of terrain!
#define REFRACT_AMOUNT 1.00 //Multiplier for the amount of refraction applied to water [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00 2.50 3.00 3.50 4.00 4.50 5.00]
#define UNDERWATER_BLUR 8 //Blurs the world while underwater [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define UNDERWATER_FOG //Applies fog to water
//#define VANILLA_LIGHTMAP //Uses vanilla light colors instead of custom ones. Requires optifine 1.12.2 HD_U_D1 or later!
#define WATER_BLUR 4 //Blurs things behind water [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define WATER_NORMALS //Distorts things reflected by water. Has no effect when reflections are disabled!
#define WATER_REFRACT //Distorts things behind water

#define CLOUD_NORMALS //Dynamically light clouds based on weather they're facing towards or away from the sun. Mild performance impact!
#define FOG_DENSITY_MULTIPLIER_OVERWORLD 1.00 //How much overall fog there is in the overworld. [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00 2.50 3.00 3.50 4.00 4.50 5.00 6.00 7.00 8.00 9.00 10.00]
#define FOG_ENABLED_OVERWORLD //Enables fog in the overworld. It is recommended to have this enabled if you also have infinite oceans enabled!
#define FOG_HEIGHT_MULTIPLIER_OVERWORLD 32.0 //Controls how much denser fog is at lower altitudes [16.0 24.0 32.0 48.0 64.0 96.0 128.0 192.0 256.0 384.0 512.0 768.0 1024.0]
#define INFINITE_OCEANS //Simulates water out to the horizon instead of just your render distance.
#define OVERWORLD_FOG_SATURATION_BOOST 1.25 //Makes the horizon blue-er [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50]
#define OVERWORLD_HORIZON_HEIGHT 0.2 //How far above the horizon the fog color will be applied [0.001 0.002 0.003 0.004 0.005 0.0075 0.01 0.02 0.03 0.04 0.05 0.075 0.1 0.2 0.3 0.4 0.5 0.75 1.0]
#define OVERWORLD_SKY_SATURATION_BOOST 1.50 //Makes the sky blue-er [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50]
#define RAIN_BLUR 10 //Blurs the world while raining [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define RAINBOWS //If enabled, rainbows will appear when the weather changes from rainy to clear
#define SEA_LEVEL 63 //Sea level for infinite oceans. Change this if you use custom worldgen. [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256]

uniform bool isSpectator;
uniform float adjustedTime;
uniform float aspectRatio;
uniform float blindness;
uniform float darknessLightFactor;
uniform float day;
uniform float far;
uniform float fogEnd;
uniform float fov;
uniform float frameTimeCounter;
uniform float night;
uniform float nightVision;
uniform float phase;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float rainStrength;
uniform float screenBrightness;
uniform float sunset;
uniform float wetness;
uniform int bedrockLevel = 0;
uniform int heightLimit = 384;
uniform int isEyeInWater;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D composite;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux4;
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D noisetex;
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
uniform vec4 lightningBoltPosition;

#ifdef CLOUDS
	varying float cloudDensityModifier; //Random fluctuations every few minutes.
#endif
#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
	varying float dofDistance; //Un-projected centerDepthSmooth
#endif
varying float eyeAdjust; //How much brighter to make the world
varying vec2 texcoord;
#ifdef CLOUDS
	varying vec3 cloudColor; //Color of the side of clouds facing away from the sun.
	varying vec3 cloudIlluminationColor; //Color of the side of clouds facing towards the sun.
#endif
varying vec3 shadowColor; //Color of shadows. Sky-colored, to simulate indirect lighting.
varying vec3 skyLightColor; //Color of sky light. Is usually white during the day, and very dark blue at night.
#ifdef CLOUDS
	varying vec4 cloudInsideColor; //Color to render over your entire screen when inside a cloud.
#endif
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
//required on older versions of optifine for its option-parsing logic.
#ifdef BLUR_ENABLED
#endif
*/

const float actualSeaLevel = SEA_LEVEL - 0.1111111111111111; //water source blocks are 8/9'ths of a block tall, so SEA_LEVEL - 1/9.

const int noiseTextureResolution = 256;
const float invNoiseRes = 1.0 / float(noiseTextureResolution);

//sines and cosines of multiples of the golden angle (~2.4 radians)
const vec2 goldenOffset0 = vec2( 0.675490294261524, -0.73736887807832 ); //2.39996322972865332
const vec2 goldenOffset1 = vec2(-0.996171040864828,  0.087425724716963); //4.79992645945731
const vec2 goldenOffset2 = vec2( 0.793600751291696,  0.608438860978863); //7.19988968918596
const vec2 goldenOffset3 = vec2(-0.174181950379306, -0.98471348531543 ); //9.59985291891461
const vec2 goldenOffset4 = vec2(-0.53672805262632,   0.843755294812399); //11.9998161486433
const vec2 goldenOffset5 = vec2( 0.965715074375778, -0.259604304901489); //14.3997793783719
const vec2 goldenOffset6 = vec2(-0.887448429245268, -0.460907024713344); //16.7997426081006
const vec2 goldenOffset7 = vec2( 0.343038630874082,  0.939321296324125); //19.1997058378292
const vec2 goldenOffset8 = vec2( 0.38155640847493,  -0.924345556137807); //21.5996690675579
const vec2 goldenOffset9 = vec2(-0.905734272555614, -0.04619144594037 ); //23.9996322972865

const vec3 blockLightColorNear   = vec3(1.0,   0.85,  0.7); //color of block lights when the player is near a light source.
const vec3 blockLightColorFar    = vec3(1.0,   0.5,   0.15); //color of block lights when the player is far away from a light source.
const vec3 nightVisionLightColor = vec3(0.375, 0.375, 0.5);

const float waterNoiseScale = 0.0625;
const float waterNoiseSpeed = 2.0;
const float iceNoiseScale   = 1.0;

const float heatRefractionScale          = 0.125;
const float heatRefractionSpeed          = 0.125;

const float lavaOverlayResolution                     = 24.0;
const float lavaOverlayHeatRefractionOffsetMultiplier = lavaOverlayResolution * 2.0;
//final color is noise * lavaOverlayNoiseColor + lavaOverlayBaseColor,
//where noise is in the range -1 to +1.
const vec3 lavaOverlayBaseColor  = vec3(1.0,   0.5, 0.0);
const vec3 lavaOverlayNoiseColor = vec3(0.375, 0.5, 0.5);

#ifdef CROSS_PROCESS
	const vec3 sunGlowColor  = vec3(1.0,   1.0,   1.0 ); //Mixed with sky color based on distance from sun
	const vec3 moonGlowColor = vec3(0.075, 0.1,   0.2 ); //Mixed with sky color based on distance from moon
	const vec3 nightSkyColor = vec3(0.02,  0.025, 0.05); //Added to sky color at night to avoid it being completely black
#else
	const vec3 sunGlowColor  = vec3(0.8,   0.9,   1.0 ); //Mixed with sky color based on distance from sun
	const vec3 moonGlowColor = vec3(0.1,   0.1,   0.2 ); //Mixed with sky color based on distance from moon
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

const vec3 cloudIlluminationColorFromFullMoon  = vec3(0.1,  0.15, 0.25);
const vec3 cloudIlluminationColorFromNewMoon   = vec3(0.01, 0.02, 0.03);
const vec3 cloudIlluminationColorFromLightning = vec3(0.9,  0.95, 1.0 );

const vec3 sunReflectionColorDuringTheDay = vec3(1.0, 0.875, 0.75);
const vec3 sunReflectionColorAtSunset     = vec3(1.0, 0.5,   0.25);

//ok so the math of my sun reflections is a bit non-intuitive.
//increasing the brightness will do just that, but it also makes the sun look bigger.
//increasing the inverse brightness will make it darker without changing the size very much.
//the two of these can be used to make the sun look as big or bright as you want,
//but it will probably a bit of experimentation to get the sun to look exactly the way you want.
const float sunReflectionBrightness        = 0.025; //this value should be slightly bigger than 0.
const float sunReflectionInverseBrightness = 1.001; //this value should be slightly bigger than 1.

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).
float lengthSquared2(vec2 v) { return dot(v, v); }
float lengthSquared3(vec3 v) { return dot(v, v); }

float interpolateSmooth1(float x) { return x * x * (3.0 - 2.0 * x); }
vec2  interpolateSmooth2(vec2  v) { return v * v * (3.0 - 2.0 * v); }
vec3  interpolateSmooth3(vec3  v) { return v * v * (3.0 - 2.0 * v); }

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

vec2 heatRefractionOffset() {
	if (HEAT_REFRACTION == 0.0) {
		return vec2(0.0);
	}
	else {
		vec2 coord = gl_FragCoord.xy * invNoiseRes * heatRefractionScale;
		float time = frameTimeCounter * heatRefractionSpeed;
		coord.y -= time;
		vec2 offset = vec2(-1.5);
		offset += texture2D(noisetex, coord).rb;
		offset += texture2D(noisetex, vec2(coord.x - time, coord.y)).rb;
		offset += texture2D(noisetex, vec2(coord.x + time, coord.y)).rb;
		return offset * vec2(pixelSizeX, pixelSizeY);
	}
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

vec2 waterNoise(vec2 coord, float time) {
	coord *= invNoiseRes;

	vec2 noise = vec2(0.0);
	noise += (texture2D(noisetex, (coord + goldenOffset0 * time)      ).rg - 0.5);          //1.0 / 1.0
	noise += (texture2D(noisetex, (coord + goldenOffset1 * time) * 1.5).rg - 0.5) * 0.6666; //1.0 / 1.5
	noise += (texture2D(noisetex, (coord + goldenOffset2 * time) * 2.0).rg - 0.5) * 0.5;    //1.0 / 2.0
	noise += (texture2D(noisetex, (coord + goldenOffset3 * time) * 2.5).rg - 0.5) * 0.4;    //1.0 / 2.5
	noise += (texture2D(noisetex, (coord + goldenOffset4 * time) * 3.0).rg - 0.5) * 0.3333; //1.0 / 3.0
	noise += (texture2D(noisetex, (coord + goldenOffset5 * time) * 3.5).rg - 0.5) * 0.2857; //1.0 / 3.5
	noise += (texture2D(noisetex, (coord + goldenOffset6 * time) * 4.0).rg - 0.5) * 0.25;   //1.0 / 4.0
	return noise;
}

vec2 waterNoiseLOD(vec2 coord, float distance) {
	float lod = log2(distance * waterNoiseScale); //level of detail
	float scale = floor(lod);
	coord *= exp2(-scale); //each time the distance doubles, so will the scale factor
	float middle = fract(lod);
	float time = frameTimeCounter * invNoiseRes * waterNoiseSpeed;

	vec2 noise1 = waterNoise(coord, time / max(scale, 1.0));
	vec2 noise2 = waterNoise(coord * 0.5, time / max(scale + 1.0, 1.0));

	return mix(noise1, noise2, interpolateSmooth1(middle)) * REFRACT_AMOUNT;
}

vec3 iceNoise(vec2 coord) {
	coord *= invNoiseRes;

	vec3 noise = vec3(0.0);
	noise += texture2D(noisetex, coord        ).rgb;
	noise += texture2D(noisetex, coord * 0.5  ).rgb;
	noise += texture2D(noisetex, coord * 0.25 ).rgb;
	noise += texture2D(noisetex, coord * 0.125).rgb;
	noise -= 2.0; //0.5 * 4.0
	return noise;
}

vec3 iceNoiseLOD(vec2 coord, float distance) {
	float lod = log2(distance * iceNoiseScale); //level of detail
	float scale = exp2(-floor(lod)); //each time the distance doubles, so will the scale factor
	coord *= scale;
	float middle = fract(lod);

	vec3 noise1 = iceNoise(coord      );
	vec3 noise2 = iceNoise(coord * 0.5);

	return mix(noise1, noise2, interpolateSmooth1(middle));
}

vec3 calcSkyColor(vec3 viewPosNorm) {
	float upDot = dot(viewPosNorm, upPosNorm) * 2.0; //not much, what's up with you?
	bool top = upDot > 0.0;
	float sunDot = dot(viewPosNorm, sunPosNorm) * 0.5 + 0.5;
	float rainCoefficient = max(rainStrength, wetness);
	vec3 color;
	vec3 skyclr = skyColor;
	skyclr.rg = mix(skyclr.bb, skyclr.rg, OVERWORLD_SKY_SATURATION_BOOST);
	skyclr = mix(skyclr, fogColor * 0.65, rainCoefficient);
	vec3 fogclr = fogColor;
	fogclr.rg = mix(fogclr.bb, fogclr.rg, OVERWORLD_FOG_SATURATION_BOOST);
	fogclr *= (1.0 - rainCoefficient * 0.25) * (1.0 - nightVision * night * 0.75);

	if (top) {
		color = skyclr + nightSkyColor * (1.0 - day) * (1.0 - rainStrength); //avoid pitch black sky at night
		if (day > 0.001) color = mix(color, sunGlowColor,  0.75 / ((1.0 - sunDot) * 16.0 + 1.0) * day   * (1.0 - rainStrength * 0.75)); //make the sun illuminate the sky around it
		else             color = mix(color, moonGlowColor, 0.75 / (       sunDot  * 16.0 + 1.0) * night * (1.0 - rainStrength       ) * phase); //make the moon illuminate the sky around it
	}
	else color = fogclr;

	if (sunset > 0.001 && rainCoefficient < 0.999) {
		vec3 sunsetColor = interpolateSmooth3(clamp(sunsetColorForSky - adjustedTime + upDot + sunDot * 0.2 * (1.0 - night), 0.0, 1.0)); //main sunset gradient
		sunsetColor = mix(fogclr, sunsetColor, (sunDot * 0.5 + 0.5) * sunset * (1.0 - rainCoefficient)); //fade in at sunset and out when not looking at the sun
		color = mix(color, sunsetColor, fogify(upDot, OVERWORLD_HORIZON_HEIGHT)); //mix with final color based on how close we are to the horizon
	}
	else if (top) color = mix(color, fogclr, fogify(upDot, OVERWORLD_HORIZON_HEIGHT));

	return color;
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

#ifdef CLOUDS
	#ifdef OLD_CLOUDS
		//finds random value at location, as well as the slope at that location if needed.
		//happens to generate noise that looks similar to minecraft's native pixellated clouds.
		vec3 cloudNoise(vec2 coord, float size, float heightOffset, bool needNormals) {
			coord /= size;

			vec2 middle = fract(coord);
			vec4 corners = vec4(coord - middle + 0.5, 0.0, 0.0);
			corners.zw = corners.xy + 1.0;
			corners *= invNoiseRes;
			//vec4 corners = (vec4(floor(coord), ceil(coord)) + 0.5) * invNoiseRes;

			float r00 = texture2D(noisetex, corners.xy).r; //random value at the (0, 0) corner
			float r01 = texture2D(noisetex, corners.xw).r; //random value at the (0, 1) corner
			float r10 = texture2D(noisetex, corners.zy).r; //random value at the (1, 0) corner
			float r11 = texture2D(noisetex, corners.zw).r; //random value at the (1, 1) corner

			vec2 mixlvl = interpolateSmooth2(middle); //non-linear interpolation

			float height = mix(mix(r00, r10, mixlvl.x), mix(r01, r11, mixlvl.x), mixlvl.y) * 2.0 - 1.0 + heightOffset; //non-linear interpolation between the 4 corners
			if (needNormals && height > 0.0 && night < 0.999) {
				vec2 dmixlvl = interpolateSmooth2(1.0 - abs(middle * 2.0 - 1.0));

				float dx = mix((r00 - r10) * dmixlvl.x, (r01 - r11) * dmixlvl.x, mixlvl.y); //slope in x direction
				float dy = mix((r00 - r01) * dmixlvl.y, (r10 - r11) * dmixlvl.y, mixlvl.x); //slope in y direction
				return vec3(dx, dy, height);
			}
			else return vec3(0.0, 0.0, height);
		}

		//returns color and opacity of clouds
		vec4 drawClouds(in vec3 cloudPosPlayer, in vec3 viewPosNorm, inout float height, in bool vshflag) {
			if ((night > 0.999 && rainStrength > 0.999) || blindness > 0.999) return vec4(0.0); //no point rendering clouds when you can't even see them.

			vec2 skyPos = cloudPosPlayer.xz + actualCameraPosition.xz;
			skyPos.x += frameTimeCounter / 1.5;
			float clumpingFactor = 1.5 * (cloudNoise(skyPos, 64.0, 0.0, false).z + wetness); //makes denser and less dense regions of clouds
			if (clumpingFactor > -1.0) {
				vec3 noiseData = cloudNoise(skyPos, 12.0, clumpingFactor, true);
				if (noiseData.z > 0.0) {
					if (height > 0.0) {
						height = 1.0 - height / noiseData.z;
						if (height < 0.0) return vec4(0.0);
					}
					vec3 color;
					//add more rough-ness to clouds. except at night, since they're solid black at night anyway. also less roughness at sunset, since it's more noticeable at sunset.
					if (night < 0.999) {
						vec2 moreNoise = vec2(0.0);
						moreNoise += texture2D(noisetex, skyPos / 3.5 * invNoiseRes).gb;
						moreNoise += texture2D(noisetex, skyPos       * invNoiseRes).gb / 4.0;
						moreNoise = (moreNoise / 2.5 - 0.25) * noiseData.z * (day + 1.0);
						noiseData.xy += moreNoise;

						vec3 normal = vec3(noiseData.x, noiseData.z * sign(actualCameraPosition.y - (bedrockLevel + heightLimit)), noiseData.y);
						if (vshflag) normal.y *= 1.0 - height; //interpolate normal Y value when flying through clouds
						normal = normalize(mat3(gbufferModelView) * normal); //rotate to be in view space, and normalize.

						float lightAmt = dot(normal, sunPosNorm) * 0.5 + 0.5; //sun illumination
						if (actualCameraPosition.y < bedrockLevel + heightLimit) {
							lightAmt *= fogify(noiseData.z, 1.25); //decrease light near the centers of the underside of clouds
							lightAmt += square(max(dot(viewPosNorm, sunPosNorm) * 3.0 - 2.0, 0.0)) * fogify(noiseData.z - wetness * 0.5, 0.25); //allow sun to "shine through" clouds where density is low, and apply bonus when raining
						}
						else {
							lightAmt *= lightAmt; //add more contrast to the tops of clouds
						}

						color = mix(cloudColor, cloudIlluminationColor, lightAmt);
					}
					else {
						color = vec3(0.0);
					}

					float alpha = 1.0 - fogify(noiseData.z + clamp(clumpingFactor, 0.0, noiseData.z), 0.25);

					return vec4(color, alpha) * (1.0 - blindness);
				}
			}
			return vec4(0.0);
		}
	#else
		//finds random value at location, as well as the slope at that location if needed.
		vec3 cloudNoise(vec2 coord) {
			vec2 middle = fract(coord);
			vec4 corners = vec4(coord - middle + 0.5, 0.0, 0.0);
			corners.zw = corners.xy + 1.0;
			corners *= invNoiseRes;
			//vec4 corners = (vec4(floor(coord), ceil(coord)) + 0.5) * invNoiseRes;
			//ivec4 corners = ivec4(mod(vec4(floor(coord), ceil(coord)), noiseTextureResolution));

			float r00 = texture2D(noisetex, corners.xy).r; //random value at the (0, 0) corner
			float r01 = texture2D(noisetex, corners.xw).r; //random value at the (0, 1) corner
			float r10 = texture2D(noisetex, corners.zy).r; //random value at the (1, 0) corner
			float r11 = texture2D(noisetex, corners.zw).r; //random value at the (1, 1) corner

			vec2 mixlvl = interpolateSmooth2(middle); //non-linear interpolation

			float height = mix(mix(r00, r10, mixlvl.x), mix(r01, r11, mixlvl.x), mixlvl.y) - 0.5; //non-linear interpolation between the 4 corners
			#ifdef CLOUD_NORMALS
				vec2 dmixlvl = interpolateSmooth2(1.0 - abs(middle * 2.0 - 1.0));

				float dx = mix((r00 - r10) * dmixlvl.x, (r01 - r11) * dmixlvl.x, mixlvl.y); //slope in x direction
				float dy = mix((r00 - r01) * dmixlvl.y, (r10 - r11) * dmixlvl.y, mixlvl.x); //slope in y direction
				return vec3(dx, dy, height);
			#else
				return vec3(0.0, 0.0, height);
			#endif
		}

		//returns color and opacity of clouds
		vec4 drawClouds(in vec3 cloudPosPlayer, in vec3 viewPosNorm, inout float height, in bool vshflag) {
			if ((night > 0.999 && rainStrength > 0.999 && lightningBoltPosition.w < 0.5) || blindness > 0.999) return vec4(0.0); //no point rendering clouds when you can't even see them.

			vec2 skyPos = cloudPosPlayer.xz + actualCameraPosition.xz;
			skyPos.x += frameTimeCounter; //apply wind

			skyPos /= heightLimit; //scale
			float time = frameTimeCounter * 0.0078125;
			vec3 noise = vec3(0.0); //x and y = normal data, z = height

			noise += cloudNoise((skyPos + time * goldenOffset0)       ) * 2.0;
			noise += cloudNoise((skyPos + time * goldenOffset1) *  2.0);
			noise += cloudNoise((skyPos + time * goldenOffset2) *  4.0) * 0.5;
			noise += cloudNoise((skyPos + time * goldenOffset3) *  8.0) * 0.25;
			noise += cloudNoise((skyPos + time * goldenOffset4) * 16.0) * 0.125;

			//add more detail without calculating interpolation or normals (since both of those are slower than fetching a single random number)
			skyPos *= invNoiseRes;
			time *= invNoiseRes;
			noise.z += texture2D(noisetex, (skyPos + time * goldenOffset5) *  32.0).r * 0.0625;
			noise.z += texture2D(noisetex, (skyPos + time * goldenOffset6) *  64.0).r * 0.03125;
			noise.z += texture2D(noisetex, (skyPos + time * goldenOffset7) * 128.0).r * 0.015625;
			noise.z += texture2D(noisetex, (skyPos + time * goldenOffset8) * 256.0).r * 0.0078125;
			noise.z += texture2D(noisetex, (skyPos + time * goldenOffset9) * 512.0).r * 0.00390625;

			noise.z += cloudDensityModifier; //random density fluctuations every few minutes
			noise.z /= max(cloudDensityModifier, 0.0) + 1.0; //scale so as not to be solid gray when density is ludicrously high
			noise.z += wetness; //bias when raining

			if (noise.z > 0.0) { //there are clouds here
				if (height > 0.0) { //volumetric effect handling (scale opacityModifier based on density of clouds)
					height = 1.0 - height / (1.0 - fogify(noise.z, 0.125));
					if (height < 0.0) return vec4(0.0); //clouds not dense enough for volumetric effects to apply.
				}
				#ifdef CLOUD_NORMALS
					vec3 playerNormal = vec3(noise.x, noise.z * sign(actualCameraPosition.y - (bedrockLevel + heightLimit)), noise.y);
					if (vshflag) playerNormal.y *= 1.0 - height; //interpolate normal Y value when flying through clouds
					vec3 viewNormal = normalize(mat3(gbufferModelView) * playerNormal); //rotate to be in view space, and normalize.

					vec2 lightAmt = vec2(dot(viewNormal, sunPosNorm), dot(viewNormal, -sunPosNorm)) * 0.5 + 0.5; //sun and moon illumination
					if (actualCameraPosition.y < bedrockLevel + heightLimit) {
						lightAmt *= fogify(noise.z, 0.5); //decrease light near the centers of the underside of clouds
						lightAmt.x *= 1.0 - rainStrength * 0.75; //less sunlight during rain.
						lightAmt.x += square(max(dot(viewPosNorm, sunPosNorm) * 3.0 - 2.0, 0.0)) * fogify(noise.z, 0.25) * (1.0 - rainStrength * 0.5); //allow sun to "shine through" clouds where density is low, and with slight bonus during rain (compared to everywhere else anyway)_
					}
					else {
						lightAmt *= lightAmt; //add more contrast to the tops of clouds
					}

					vec3 color = mix(cloudColor, cloudIlluminationColor, lightAmt.x); //colorize
					color += mix(cloudIlluminationColorFromNewMoon, cloudIlluminationColorFromFullMoon, lightAmt.y * phase) * night * (1.0 - rainStrength); //add lunar illumination
					if (lightningBoltPosition.w > 0.5) {
						vec2 lightningOffset = lightningBoltPosition.xz - cloudPosPlayer.xz;
						vec2 semiNormalizedLightningOffset = lightningOffset / (length(lightningOffset) + (heightLimit / 16.0));
						float lightningAmount = dot(semiNormalizedLightningOffset, playerNormal.xz) * 0.5 + 0.5;
						lightningAmount *= 1.0 / (lengthSquared2(lightningOffset * (0.5 / heightLimit)) + 1.0);
						color = mix(color, cloudIlluminationColorFromLightning, lightningAmount);
					}
					float alpha = 1.0 - fogify(noise.z , 0.0625); //more opaque in center, less opaque around edges
					return vec4(color, alpha) * (1.0 - blindness);
				#else
					float lightAmt = fogify(noise.z, 0.25); //more light on edges than center
					if (actualCameraPosition.y > bedrockLevel + heightLimit) lightAmt = lightAmt * -0.5 + 1.0; //reverse and scale when above clouds

					vec3 color = mix(cloudColor, cloudIlluminationColor, lightAmt); //colorize
					color += mix(cloudIlluminationColorFromNewMoon, cloudIlluminationColorFromFullMoon, lightAmt * phase) * night * (1.0 - rainStrength); //add lunar illumination
					float alpha = 1.0 - fogify(noise.z, 0.0625); //more opaque in center, less opaque around edges
					return vec4(color, alpha) * (1.0 - blindness);
				#endif
			}
			return vec4(0.0);
		}
	#endif
#endif

Position posFromDepthtex(sampler2D depthtex) {
	Position pos;
	float depth = texture2D(depthtex, texcoord).r;
	pos.isSky = depth == 1.0;
	vec3 screen = vec3(texcoord, depth) * 2.0 - 1.0;
	vec4 tmp = gbufferProjectionInverse * vec4(screen, 1.0);
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
	if (isEyeInWater == 2 && !isSpectator) {
		vec2 coord = texcoord * lavaOverlayResolution + heatRefractionOffset() * lavaOverlayHeatRefractionOffsetMultiplier;
		coord.y = coord.y / aspectRatio + frameTimeCounter;
		coord = floor(coord) + 0.5;
		float noise = 0.0;
		noise += (texture2D(noisetex, vec2(coord.x * 0.25, coord.y * 0.25 + frameTimeCounter) * invNoiseRes).r - 0.5);
		noise += (texture2D(noisetex, vec2(coord.x * 0.5,  coord.y * 0.5  + frameTimeCounter) * invNoiseRes).r - 0.5) * 0.5;
		noise += (texture2D(noisetex, vec2(coord.x,        coord.y        + frameTimeCounter) * invNoiseRes).r - 0.5) * 0.25;
		vec3 color = noise * lavaOverlayNoiseColor + lavaOverlayBaseColor;
		gl_FragData[0] = vec4(color, 1.0);
		return; //don't need to calculate anything else since the lava overlay covers the entire screen.
	}

	vec2 tc = texcoord;

	vec3 oldaux2 = texture2D(gaux2, texcoord).rgb;
	int id = int(oldaux2.b * 10.0 + 0.1);
	vec3 normal = texture2D(gnormal, texcoord).xyz * 2.0 - 1.0;

	Position nearPos = posFromDepthtex(depthtex0);
	Position farPos = posFromDepthtex(depthtex1);

	#ifdef REFLECT
		float reflective = 0.0;
	#endif

	#ifdef CLOUDS
		bool isTCOffset = false; //tracks weather or not cloud positions need to be re-calculated due to water/ice refractions
	#endif

	float blur = 0.0;

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		blur = interpolateSmooth1(min(abs(farPos.blockDist - dofDistance) / dofDistance, 1.0)) * DOF_STRENGTH;
	#endif

	#if defined(BLUR_ENABLED) && WATER_BLUR != 0
		float waterBlur = float(WATER_BLUR); //slightly more dynamic than other types of blur, as high fog density will decrease this value, and being near a reflection of the sun will increase it.
	#endif

	if (id == 1) { //water or infinite oceans
		#ifdef REFLECT
			reflective = 0.5;
		#endif

		#ifdef INFINITE_OCEANS
			if (nearPos.isSky) {
				float diff = actualSeaLevel - actualCameraPosition.y;
				nearPos.player = vec3(nearPos.playerNorm.xz * (diff / nearPos.playerNorm.y), diff).xzy;
				nearPos.world = nearPos.player + actualCameraPosition;
				nearPos.blockDist = length(nearPos.player);
				nearPos.viewDist = nearPos.blockDist / far;
				nearPos.isSky = false;
			}
		#endif

		#if defined(WATER_REFRACT) || (defined(WATER_NORMALS) && defined(REFLECT))
			vec3 newPos = nearPos.world;
			ivec2 swizzles;
			float multiplier = 1.0;
			if (abs(normal.y) > 0.1) { //top/bottom surface
				if (abs(normal.y) < 0.999) newPos.xz -= normalize(normal.xz) * (frameTimeCounter * 3.0);
				else multiplier = (oldaux2.g * (0.75 - night * 0.375) + 0.25) + (oldaux2.g * min(rainStrength, wetness) * 1.5);
				swizzles = ivec2(0, 2);
			}
			else {
				newPos.y += frameTimeCounter * 4.0;
				if (abs(normal.x) < 0.02) swizzles = ivec2(0, 1);
				else swizzles = ivec2(2, 1);
			}

			vec2 offset = waterNoiseLOD(vec2(newPos[swizzles[0]], newPos[swizzles[1]]), nearPos.blockDist) * (multiplier * 0.015625); //witchcraft.
			#ifdef WATER_NORMALS
				normal[swizzles[0]] += offset[0] * 4.0;
				normal[swizzles[1]] += offset[1] * 4.0;
				normal = normalize(normal);
			#endif

			#ifdef WATER_REFRACT
				vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio) / max(nearPos.blockDist * 0.0625, 1.0);
				vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
				if (dot(normal, newnormal) > 0.9) { //don't offset on the edges of water
					tc = newtc;

					#ifdef CLOUDS
						isTCOffset = true;
					#endif
				}
			#endif
		#endif
	}
	else if (id == 2) { //stained glass
		#ifdef REFLECT
			reflective = 0.25;
		#endif

		#if defined(BLUR_ENABLED) && GLASS_BLUR != 0
			blur = max(blur, float(GLASS_BLUR));
		#endif
	}
	else if (id == 3 || id == 4) { //ice and held ice
		#ifdef REFLECT
			reflective = 0.25;
		#endif

		#if defined(BLUR_ENABLED) && ICE_BLUR != 0
			blur = max(blur, float(ICE_BLUR));
		#endif

		#if defined(ICE_REFRACT) || (defined(ICE_NORMALS) && defined(REFLECT))
			vec3 offset;
			if (id == 3) {
				vec2 coord = (abs(normal.y) < 0.001 ? vec2(nearPos.world.x + nearPos.world.z, nearPos.world.y) : nearPos.world.xz);
				offset = iceNoiseLOD(coord * 256.0, nearPos.blockDist) * 0.0078125;
			}
			else {
				vec2 coord = gl_FragCoord.xy + 0.5;
				offset = iceNoise(coord * 0.5) * 0.0078125;
			}

			#ifdef ICE_REFRACT
				vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio);
				vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
				if (dot(normal, newnormal) > 0.9) { //don't offset on the edges of ice
					tc = newtc;

					#ifdef CLOUDS
						isTCOffset = true;
					#endif
				}
			#endif

			#ifdef ICE_NORMALS
				normal = normalize(normal + offset * 8.0);
			#endif
		#endif
	}

	vec3 aux2 = texture2D(gaux2, tc).rgb;
	if (abs(aux2.b - oldaux2.b) > 0.02) {
		tc = texcoord;
		aux2 = texture2D(gaux2, tc).rgb;

		#ifdef CLOUDS
			isTCOffset = false;
		#endif
	}

	vec4 c = texture2D(gcolor, tc);
	vec3 color = c.rgb;
	float transparentAlpha = c.a; //using gcolor to store composite's alpha
	vec4 transparent = texture2D(composite, tc); //transparency of closest object to the camera

	#if defined(BLUR_ENABLED) && UNDERWATER_BLUR != 0
		if (isEyeInWater == 1) blur = float(UNDERWATER_BLUR);
	#endif

	#ifdef CLOUDS
		float cloudDiff = (bedrockLevel + heightLimit) - actualCameraPosition.y;
		vec3 baseCloudPos = nearPos.playerNorm;
		float cloudDist;
		vec4 cloudclr = vec4(0.0);
		//don't render clouds below you if you're below them, and vise versa.
		bool cloudy = sign(cloudDiff) == sign(baseCloudPos.y);
		if (cloudy) {
			//calculate base cloud plane position
			baseCloudPos = vec3(baseCloudPos.xz * (cloudDiff / baseCloudPos.y), cloudDiff).xzy;
			cloudDist = lengthSquared3(baseCloudPos) * 0.999; //avoid z-fighting by making clouds a little bit closer
			float opacityModifier = -1.0;
			//additional logic if there's terrain in front of the clouds (used for fake volumetric effects)
			if (!nearPos.isSky && nearPos.blockDist * nearPos.blockDist < cloudDist) {
				opacityModifier = abs(nearPos.world.y - (bedrockLevel + heightLimit)) * (1.0 / 16.0);
				if (opacityModifier < 1.0) { //maximum cloud density
					baseCloudPos = nearPos.player;
					cloudDist = nearPos.blockDist * 0.999;
				}
				else { //pos is outside range of fake volumetric effects, check farPos next.
					opacityModifier = -1.0;
					if (!farPos.isSky) { //opaque object exists here
						opacityModifier = abs(farPos.world.y - (bedrockLevel + heightLimit)) * (1.0 / 16.0);
						if (opacityModifier < 1.0 && farPos.blockDist < cloudDist) { //within volumetric range
							baseCloudPos = farPos.player;
							cloudDist = farPos.blockDist * 0.999;
						}
						else opacityModifier = -1.0;
						cloudy = farPos.blockDist > cloudDist; //true if there's clouds between the terrain and the transparent thing
					} //opaque object exists here too
				} //pos is outside range of fake volumetric effects, check farPos next.
			} //something in front of terrain

			if (cloudy) {
				if (isTCOffset && nearPos.blockDist * nearPos.blockDist < cloudDist) { //re-calculate position to account for water refraction.
					baseCloudPos = normalize((gbufferModelViewInverse * (gbufferProjectionInverse * vec4(tc * 2.0 - 1.0, 1.0, 1.0))).xyz);
					baseCloudPos = vec3(baseCloudPos.xz / baseCloudPos.y * cloudDiff, cloudDiff).xzy;
					//not re-calculating distance because it's not really all that necessary.
				}
				cloudDist = sqrt(cloudDist);
				cloudclr = drawClouds(baseCloudPos, nearPos.viewNorm, opacityModifier, false);

				cloudclr.a *= 64.0 / (lengthSquared2(baseCloudPos.xz / baseCloudPos.y) + 64.0); //reduce opacity in the distance

				if (cloudclr.a > 0.001) {
					if (opacityModifier > 0.0 && opacityModifier < 1.0) { //in the fadeout range
						cloudclr.a *= interpolateSmooth1(opacityModifier);
					}
				}
				else cloudy = false; //no need to render clouds that don't exist at this location
			}
		}
	#endif

	if (transparentAlpha > 0.001) {
		#ifdef CLOUDS
			if (cloudy && nearPos.blockDist < cloudDist) color = mix(color, cloudclr.rgb, cloudclr.a);
		#endif

		#ifdef ALT_GLASS
			if (id == 2) {
				vec3 transColor = transparent.rgb / transparentAlpha;
				color *= transColor * (2.0 - transColor); //because the default colors are too dark to be used.

				float skylight = aux2.g;
				float blocklight = aux2.r;
				float heldlight = 0.0;

				color += transColor * calcMainLightColor(blocklight, skylight, heldlight, nearPos) * 0.125 * (1.0 - blindness);
			}
			else
		#endif
				color = mix(color, transparent.rgb / transparentAlpha, transparentAlpha);
	}
	#ifdef CLOUDS
		else if (cloudy && (/* dist < cloudDist || */ id != 1 || isEyeInWater == 1)) color = mix(color, cloudclr.rgb, cloudclr.a);
	#endif

	#ifdef REFLECT
		reflective *= aux2.g * aux2.g * (1.0 - blindness);
		vec3 reflectedPos;
		if (isEyeInWater == 0 && reflective > 0.001) { //sky reflections
			vec3 newnormal = mat3(gbufferModelView) * normal;
			reflectedPos = reflect(nearPos.viewNorm, newnormal);
			vec3 skyclr = calcSkyColor(reflectedPos);
			float posDot = dot(-nearPos.viewNorm, newnormal);
			color += skyclr * square(square(1.0 - max(posDot, 0.0))) * reflective;
		}
	#endif

	if (id > 0) { //everything that I've currently assigned effects to so far needs fog to be done in this stage.
		if (isEyeInWater == 1) {
			#ifdef UNDERWATER_FOG
				float actualEyeBrightness = eyeBrightnessSmooth.y / 240.0;
				#ifdef BRIGHT_WATER
					actualEyeBrightness = actualEyeBrightness * 0.5 + 0.5;
				#endif
				color = calcUnderwaterFogColor(color, nearPos.blockDist, actualEyeBrightness) * (1.0 - blindness);
			#endif
		}
		else {
			#ifdef FOG_ENABLED_OVERWORLD
				vec3 fogclr = calcFogColor(nearPos.viewNorm);
				fogclr += fract(dot(gl_FragCoord.xy, vec2(0.25, 0.5))) * 0.00390625; //dither to match sky
				float fogAmount = calcFogAmount(nearPos, nearPos.blockDist / fogEnd);
				color = mix(fogclr * min(max(aux2.g * 2.0, eyeBrightness.y / 120.0), 1.0) * (1.0 - blindness), color, fogAmount);
				#if defined(BLUR_ENABLED) && WATER_BLUR != 0
					waterBlur *= fogAmount;
				#endif
			#endif
		}
	}

	//sun reflections bypasses fog.
	#ifdef REFLECT
		reflective *= day * (1.0 - rainStrength);
		if (isEyeInWater == 0 && reflective > 0.001) {
			vec3 sunColor = mix(sunReflectionColorAtSunset, sunReflectionColorDuringTheDay, day);
			float sunDot = dot(reflectedPos, sunPosNorm);
			float reflectionAmount = sunReflectionBrightness / (sunReflectionInverseBrightness - sunDot);

			color = mix(vec3(1.0), color, exp2(-sunColor * reflectionAmount * reflective));

			#if defined(BLUR_ENABLED) && WATER_BLUR != 0
				waterBlur = clamp((sunDot - 0.75) * 16.0, waterBlur, WATER_BLUR); //no more than WATER_BLUR, and no less than what it was originally.
			#endif
		}
	#endif

	//color = min(color, 1.0); //reflections (and possibly other things) can go above maximum brightness

	#ifdef CLOUDS
		if (cloudy && (id == 1 || transparentAlpha > 0.001) && nearPos.blockDist > cloudDist) color = mix(color, cloudclr.rgb, cloudclr.a);
		color = mix(color, cloudInsideColor.rgb, cloudInsideColor.a);
	#endif

	#if defined(BLUR_ENABLED) && RAIN_BLUR != 0
		if (wetness > 0.001) {
			float skylight = texture2D(gaux1, tc).g;

			float heightModifier = 1.0;

			#ifdef CLOUDS
				heightModifier = fogify(max(actualCameraPosition.y - (bedrockLevel + heightLimit), 0.0), 6.25); //less rain blur above cloud height
			#endif

			blur += wetness * heightModifier * float(RAIN_BLUR) * (farPos.isSky ? 0.5 : max(eyeBrightnessSmooth.y / 120.0, skylight * 2.0) * nearPos.viewDist);
		}
	#endif

	#if defined(BLUR_ENABLED) && WATER_BLUR != 0
		if (id == 1 && isEyeInWater == 0) blur += waterBlur;
	#endif

	#ifdef BLUR_ENABLED
		blur /= 256.0;
	#endif

	color *= mix(vec3(eyeAdjust), vec3(1.0), color);

/* DRAWBUFFERS:6 */
	gl_FragData[0] = vec4(color, 1.0 - blur); //gaux3
}