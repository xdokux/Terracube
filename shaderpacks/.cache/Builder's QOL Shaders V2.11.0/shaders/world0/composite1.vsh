#version 120

#define BLUR_ENABLED //Is blur enabled at all?
#define BRIGHT_WATER //Overrides light levels under water to be higher
#define CLOUDS //3D clouds (partially volumetric too). Mild performance impact!
//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DOF_STRENGTH 0 //Blurs things that are at a different distance than whatever's in the center of your screen [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define DYNAMIC_LIGHT_FLICKER 8 //How much certain dynamic lights (like torches) will flicker [0 1 2 3 4 5 6 8 12 16 24 32 48 64]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
//#define OLD_CLOUDS //Makes fancy clouds more square-shaped

#define CLOUD_DENSITY_AVERAGE 0.0 //Average cloud density. Higher value means more clouds [-2.0 -1.9 -1.8 -1.7 -1.6 -1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.4 -0.3 -0.2 -0.1 0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define CLOUD_DENSITY_VARIANCE 1.5 //How far above or below the average cloud density will go [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define CLOUD_NORMALS //Dynamically light clouds based on weather they're facing towards or away from the sun. Mild performance impact!
#define EYE_ADJUST_OVERWORLD_DARK 3.0 //Brightness multiplier for the whole screen when standing in darkness in the overworld [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define EYE_ADJUST_OVERWORLD_LIGHT 1.5 //Brightness multiplier for the whole screen when standing in bright light in the overworld [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define HARDCORE_DARKNESS 0 //0 (Off): Normal visibility at night. 1 (On): Complete darkness at night. 2 (Moon phase) Nighttime brightness is determined by the current phase of the moon. [0 1 2]

uniform float adjustedTime;
uniform float blindness;
uniform float centerDepthSmooth;
uniform float day;
uniform float frameTimeCounter;
uniform float night;
uniform float phase;
uniform float rainStrength;
uniform float sunset;
uniform float wetness;
uniform int bedrockLevel = 0;
uniform int heightLimit = 384;
uniform int heldBlockLightValue;
uniform int heldItemId;
uniform int isEyeInWater;
uniform int worldDay;
uniform int worldTime;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunPosNorm;
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
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

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

const float lavaOverlayResolution                     = 24.0;

//Overworld cloud colors are multi-dimensional because they're used by /lib/fastDrawClouds.glsl for end portal blocks.
//At night, this will be 0.
//When raining, this will be fogColor * 0.5
const vec3 cloudBaseColorDuringSunnyDays = vec3(0.48, 0.5, 0.55);

//At night, both of these will be 0.
const vec3 cloudIlluminationColorWhenSunny   = vec3(1.0,  1.0, 1.0);
const vec3 cloudIlluminationColorWhenRaining = vec3(0.45, 0.5, 0.6);

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

const vec3 cloudIlluminationColorFromFullMoon  = vec3(0.1,  0.15, 0.25);
const vec3 cloudIlluminationColorFromNewMoon   = vec3(0.01, 0.02, 0.03);
const vec3 cloudIlluminationColorFromLightning = vec3(0.9,  0.95, 1.0 );

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).
float lengthSquared2(vec2 v) { return dot(v, v); }

float interpolateSmooth1(float x) { return x * x * (3.0 - 2.0 * x); }
vec2  interpolateSmooth2(vec2  v) { return v * v * (3.0 - 2.0 * v); }

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

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

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	float eyeBlocklight = eyeBrightnessSmooth.x / 240.0;
	float eyeSkylight = eyeBrightnessSmooth.y / 240.0;
	#ifdef BRIGHT_WATER
		if (isEyeInWater == 1) eyeSkylight = eyeSkylight * 0.5 + 0.5;
	#endif
	eyeSkylight *= 1.0 - night;
	eyeAdjust = mix(EYE_ADJUST_OVERWORLD_DARK, EYE_ADJUST_OVERWORLD_LIGHT, max(eyeBlocklight, eyeSkylight));

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		vec4 v = gbufferProjectionInverse * vec4(0.0, 0.0, centerDepthSmooth * 2.0 - 1.0, 1.0);
		dofDistance = -v.z / v.w;
	#endif

	#ifdef CLOUDS
		if (wetness < 0.999) {
			//avoid some floating point precision errors on old worlds by modulus-ing the world day.
			//normally I'd just do the modulo on ints instead of floats, but if I've learned anything about GLSL, it's that it really doesn't like ints.
			//as such, I'll cast worldDay to a float instead in hopes that it won't randomly break on someone else's GPU.
			float randTime = (mod(float(worldDay), float(noiseTextureResolution)) + worldTime / 24000.0) * 5.0;
			randTime = floor(randTime) + interpolateSmooth1(fract(randTime)) + 0.5;
			cloudDensityModifier = ((texture2D(noisetex, vec2(randTime, 0.5) * invNoiseRes).r * 2.0 - 1.0) * CLOUD_DENSITY_VARIANCE + CLOUD_DENSITY_AVERAGE) * (1.0 - wetness);
			//float r0 = texelFetch2D(noisetex, ivec2(int(randTime)     % noiseTextureResolution, 0), 0).r;
			//float r1 = texelFetch2D(noisetex, ivec2(int(randTime + 1) % noiseTextureResolution, 0), 0).r;
			//cloudDensityModifier = (mix(r0, r1, interpolateSmooth1(fract(randTime))) * 3.0 - 1.5) * (1.0 - wetness);
		}
		else {
			cloudDensityModifier = 0.0;
		}

		cloudColor             = mix(cloudBaseColorDuringSunnyDays * day, fogColor * 0.5, wetness);
		cloudIlluminationColor = mix(cloudIlluminationColorWhenSunny, cloudIlluminationColorWhenRaining, wetness) * day;

		if (sunset > 0.001) {
			vec3 sunsetColor = clamp(sunsetColorForOtherThings - adjustedTime, 0.0, 1.0);
			cloudIlluminationColor = mix(cloudIlluminationColor, sunsetColor, sunset * (1.0 - wetness * 0.5));
		}

		float d = abs(actualCameraPosition.y - (bedrockLevel + heightLimit)) * (1.0 / 16.0);
		if (d < 1.0) {
			cloudInsideColor = drawClouds(vec3(0.0), vec3(0.0), d, true);
			if (cloudInsideColor.a > 0.0) {
				if (d > 0.0 && d < 1.0) cloudInsideColor.a *= interpolateSmooth1(d); //in the fadeout range
			}
		}
		else {
			cloudInsideColor = vec4(0.0);
		}
	#endif

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