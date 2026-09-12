#version 120

//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DYNAMIC_LIGHT_VIGNETTE 50 //Reduces the brightness of dynamic light around edges the of your screen [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define ENDER_ARCS //Adds bolts of plasma that arc through the nebulae. Requires ender nebulae to be enabled!
#define ENDER_NEBULAE //Adds animated nebulae to the background of the end dimension
#define ENDER_STARS //Adds blinking stars to the background of the end dimension. Stackable with nebulae/plasma.
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
//#define VANILLA_LIGHTMAP //Uses vanilla light colors instead of custom ones. Requires optifine 1.12.2 HD_U_D1 or later!

#define DESATURATE_END 0.25 //Amount to desaturate the end dimension [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define FOG_DISTANCE_MULTIPLIER_END 0.25 //How far away fog starts to appear in the end [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
//#define FOG_ENABLED_END //Enables fog in the end

uniform float blindness;
uniform float darknessLightFactor;
uniform float far;
uniform float fogEnd;
uniform float fov;
uniform float frameTimeCounter;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D depthtex1;
uniform sampler2D gaux1;
uniform sampler2D gaux3;
uniform sampler2D gaux4; //lightmap
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
#ifdef DYNAMIC_LIGHTS
	varying vec4 heldLightColor; //Color of held light source. Alpha = brightness.
#endif

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

const int gaux3Format = RGBA16;
const int gcolorFormat = RGBA16;
const int compositeFormat = RGBA16;
const int gnormalFormat = RGB16;
*/

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

const vec3 blockLightColorNear   = vec3(1.0,   0.85,  0.7); //color of block lights when the player is near a light source.
const vec3 blockLightColorFar    = vec3(1.0,   0.5,   0.15); //color of block lights when the player is far away from a light source.
const vec3 nightVisionLightColor = vec3(0.375, 0.375, 0.5);

const vec3 blocklightVibrantColorFar  = vec3(1.4, 1.0, 0.8); //Vibrant color for block lights when standing far away from a light source.
const vec3 blocklightVibrantColorNear = vec3(1.2, 1.1, 1.0); //Vibrant color for block lights when standing near a light source.

const float lavaOverlayResolution                     = 24.0;

const vec3 ambientLightColor   = vec3(0.1, 0.05, 0.2);
const vec3 ambientVibrantColor = vec3(1.0, 0.75, 1.5);

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).
float lengthSquared2(vec2 v) { return dot(v, v); }

float interpolateSmooth1(float x) { return x * x * (3.0 - 2.0 * x); }
vec2  interpolateSmooth2(vec2  v) { return v * v * (3.0 - 2.0 * v); }
vec3  interpolateSmooth3(vec3  v) { return v * v * (3.0 - 2.0 * v); }

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
		lightclr += ambientLightColor; //skylight
		lightclr += mix(blockLightColorFar, blockLightColorNear, eyeBrightnessSmooth.x / 240.0) * blocklight; //blocklight
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

#ifdef ENDER_NEBULAE
	float random(vec2 coord) {
		vec2 middle = fract(coord);
		vec4 corners = vec4(coord - middle + 0.5, 0.0, 0.0);
		corners.zw = corners.xy + 1.0;
		corners *= invNoiseRes;

		float r00 = texture2D(noisetex, corners.xy).r; //random value at the (0, 0) corner
		float r01 = texture2D(noisetex, corners.xw).r; //random value at the (0, 1) corner
		float r10 = texture2D(noisetex, corners.zy).r; //random value at the (1, 0) corner
		float r11 = texture2D(noisetex, corners.zw).r; //random value at the (1, 1) corner

		vec2 mixlvl = interpolateSmooth2(middle); //non-linear interpolation

		return mix(mix(r00, r10, mixlvl.x), mix(r01, r11, mixlvl.x), mixlvl.y); //linear interpolation between the 4 corners
	}

	//base noise algorithm for the overall cloud pattern.
	float densityNoise(vec2 pos) {
		float noise = -0.32992;
		noise += random(pos * 2.0  + goldenOffset0 * frameTimeCounter * 0.125  ) * 0.4;
		noise += random(pos * 4.0  + goldenOffset1 * frameTimeCounter * 0.0625 ) * 0.16;
		noise += random(pos * 8.0  + goldenOffset2 * frameTimeCounter * 0.04166) * 0.064;
		noise += random(pos * 16.0 + goldenOffset3 * frameTimeCounter * 0.03125) * 0.0256;
		noise += random(pos * 32.0 + goldenOffset4 * frameTimeCounter * 0.025  ) * 0.01024;
		return noise;
	}

	//noise algorithm for all the different colors
	//doesn't need as many iterations as densityNoise() because it doesn't need to be as "rough"
	//also has different speed/effect multipliers in order to fit the values I want to get out of hue().
	vec3 colorNoise(vec2 pos) {
		float noise = 0.4;
		noise += random(pos * 2.0 + goldenOffset5 * frameTimeCounter * 0.5 ) * 0.25;
		noise += random(pos * 4.0 + goldenOffset6 * frameTimeCounter * 0.25) * 0.125;
		noise += random(pos * 8.0 + goldenOffset7 * frameTimeCounter * 0.16) * 0.0625;
		return interpolateSmooth3(hue(noise)) * 0.625;
	}

	//both of these functions are quite similar, just with some slight differences in the math.
	#ifdef ENDER_ARCS
		vec4 drawNebulae(vec2 pos) {
			float noise = abs(densityNoise(pos)); //density depends on how close densityNoise() is to 0.0
			if (noise < 0.25) { //alpha calculations work within the range 0 - 0.25
				vec3 baseclr = colorNoise(pos); //nebulae color at this position
				float arclight = square(max(0.7 - noise * 8.0, 0.0)); //brighten areas that are very close to an arc (when cloudNoise() is close to 0.0)
				return vec4(mix(baseclr, vec3(1.0), arclight), square(1.0 - noise * 4.0) * 0.9); //alpha also depends on how close to an arc we are
			}
			else return vec4(0.0); //was not part of a nebula
		}
	#else
		vec4 drawNebulae(vec2 pos) {
			float noise = densityNoise(pos) + 0.125; //density depends on how close densityNoise() is to 1.0
			if (noise > 0.0) {
				vec3 baseclr = colorNoise(pos); //nebulae color at this position
				baseclr += 1.0 - fogify(noise, 0.2); //brighten areas that are close to the "center" of the nebulae (when cloudNoise() is close to 1.0)
				return vec4(baseclr, 1.0 - fogify(noise, 0.05)); //alpha also depends on how close to the "center" of the nebulae we are
			}
			else return vec4(0.0);
		}
	#endif
#endif

#ifdef ENDER_STARS
	float fade(float speed, float delay) {
		float newTime = mod(frameTimeCounter * speed, delay);
		//newTime / threshold
		if (newTime < 0.1) return newTime * 10.0;
		//1.0 - (newTime / (1.0 - threshold)) + (threshold / (1.0 - threshold));
		else return newTime * -1.1111111111111111 + 1.1111111111111111;
	}

	vec3 drawStars(vec2 pos) {
		pos *= 16.0; //increase density of stars by a factor of 16x.
		vec2 newpos = floor(pos) + 0.5; //position rounded to the nearest "square". you can immagine this imposing a grid pattern onto the sky.

		//r = random chance that this square will be a star, g = fade animation speed, b = delay before re-appearing
		//r is also used to store "brightness" of the star. if the star is above 75% brightness to start with, it gets to be rendered. (this check is ignored for ender portals)
		vec3 starData1 = texture2D(noisetex, newpos * invNoiseRes).rgb;
		float fadeAmt = fade(starData1.g * 0.1 + 0.15, starData1.b * 8.0 + 1.0);

		if (starData1.r > 0.75 && fadeAmt > 0.0) { //25% of all the "squares" in the sky will be stars
			//r = type (star-shaped vs. circular), g = size multiplier, b = color
			vec3 starData2 = texture2D(noisetex, -newpos * invNoiseRes).rgb;

			float dist;
			//star-shaped stars are smaller than circular ones, so making more of them to compensate.
			if (starData2.r < 0.25) dist = length(pos - newpos) * 2.0; //pythagorean distance
			else { //star-shaped distance (distance increases faster diagonally than cardinally)
				vec2 v = sqrt(abs(pos - newpos));
				dist = v.x + v.y;
			}

			dist *= starData2.g + 1.0; //apply random size modifier. increasing the distance has the effect of decreasing the size, since smaller distances get scaled up to the maximum distance
			dist += 1.0 - fadeAmt; //apply fading animation. again, increasing distance decreases size. when fadeAmt = 0, the star will be invisible.

			float amt = square(max(1.0 - dist, 0.0)); //apply distance calculations to brightness of the star. The closer we are to the center, the brighter it should be.

			vec3 clr = hue(starData2.b * 0.6 - 0.35) * 0.625 + 0.375; //calculate color of star based on random number.
			clr = clr * amt + amt * amt * 0.625; //actually colorize star, and make whiter near the center.

			//make some stars brighter than others
			clr *= starData1.r * 2.0 - 1.0;

			return clr;
		}
		return vec3(0.0);
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
	pos.blockDist = length(pos.view);
	pos.viewDist = pos.blockDist / far;
	pos.viewNorm = pos.view / pos.blockDist;
	pos.playerNorm = pos.player / pos.blockDist;
	pos.world = pos.player + actualCameraPosition;
	return pos;
}

void main() {
	vec2 tc = texcoord;

	Position farPos = posFromDepthtex(depthtex1);

	vec3 color = texture2D(gcolor, tc).rgb;

	if (!farPos.isSky) {
		float blocklight = texture2D(gaux1, tc).r;
		float heldlight = 0.0;

		color *= calcMainLightColor(blocklight, heldlight, farPos);

		#ifdef CROSS_PROCESS
			vec3 blockCrossColor = mix(blocklightVibrantColorFar, blocklightVibrantColorNear, eyeBrightnessSmooth.x / 240.0); //cross processing color from block lights
			vec3 finalCrossColor = mix(ambientVibrantColor, blockCrossColor, blocklight);
			color.rgb = clamp(color.rgb * finalCrossColor - (color.grr + color.bbg) * 0.1, 0.0, 1.0);
		#endif

		if (DESATURATE_END > 0.0) {
			float desatAmt = DESATURATE_END * (1.0 - max(blocklight, heldlight));
			float average = dot(color.rgb, vec3(0.25, 0.5, 0.25));
			color.rgb = mix(color.rgb, vec3(average), desatAmt);
		}

		#ifdef FOG_ENABLED_END
			color = mix(
				fogColor * (1.0 - nightVision * 0.5),
				color,
				fogify(farPos.blockDist / fogEnd, FOG_DISTANCE_MULTIPLIER_END)
			);
		#endif
	}
	#if defined(ENDER_NEBULAE) || defined(ENDER_STARS)
		else {
			vec2 skyPos = farPos.playerNorm.xz / (farPos.playerNorm.y + 1.0);
			//adding 1.0 to posNorm.y is how I get the sky to "wrap" around you.
			//if you want to visualize the effect this has, I would suggest setting color to vec3(fract(skyPos), 0.0).
			float multiplier = 8.0 / (lengthSquared2(skyPos) + 8.0); //wrapping behavior produces a mathematical singularity below you, so this hides that.

			#ifdef ENDER_NEBULAE
				vec4 cloudclr = drawNebulae(skyPos);
				color = mix(color, cloudclr.rgb, cloudclr.a * multiplier);
			#endif

			#ifdef ENDER_STARS
				vec3 starclr = drawStars(skyPos);
				color += starclr * multiplier;
			#endif
		}
	#endif

	if (blindness > 0.0) color *= interpolateSmooth1(max(1.0 - farPos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);

/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(color, texture2D(gaux3, texcoord).r); //gcolor
}