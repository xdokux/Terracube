#version 120

//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]

#define EXCLUSION_RADIUS 1.0 //Radius around the moon at which fancy stars/galaxies stop rendering [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define FANCY_STARS //Improved stars in the overworld
#define GALAXIES //Galaxies visible at night in the overworld, with even more stars inside them
#define INFINITE_OCEANS //Simulates water out to the horizon instead of just your render distance.
#define OVERWORLD_FOG_SATURATION_BOOST 1.25 //Makes the horizon blue-er [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50]
#define OVERWORLD_HORIZON_HEIGHT 0.2 //How far above the horizon the fog color will be applied [0.001 0.002 0.003 0.004 0.005 0.0075 0.01 0.02 0.03 0.04 0.05 0.075 0.1 0.2 0.3 0.4 0.5 0.75 1.0]
#define OVERWORLD_SKY_SATURATION_BOOST 1.50 //Makes the sky blue-er [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50]
#define RAINBOWS //If enabled, rainbows will appear when the weather changes from rainy to clear
#define SUN_POSITION_FIX //Enable this if the horizon "splits" at sunset when rapidly rotating your camera.

uniform float adjustedTime;
uniform float day;
uniform float night;
uniform float nightVision;
uniform float phase;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float rainStrength;
uniform float sunset;
uniform float wetness;
uniform int bedrockLevel = 0;
uniform int heightLimit = 384;
uniform int worldDay;
uniform int worldTime;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
#ifndef SUN_POSITION_FIX
uniform vec3 sunPosNorm;
#endif

#ifdef SUN_POSITION_FIX
	varying vec3 sunPosNorm;
#endif
varying vec4 starData; //rgb = star color, a = flag for weather or not this pixel is a star.

struct Position {
	vec3 viewNorm;
	vec3 playerNorm;
	float sunDot;
	//float upDot is just playerNorm.y
	float spaceFactor;
};

const float sunPathRotation = 30.0; //Angle that the sun/moon rotate at [-45.0 -40.0 -35.0 -30.0 -25.0 -20.0 -15.0 -10.0 -5.0 0.0 5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0]

const int noiseTextureResolution = 256;
const float invNoiseRes = 1.0 / float(noiseTextureResolution);

#if defined(FANCY_STARS) || defined(GALAXIES)
	const mat2 starRotation = mat2(
		cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994),
		sin(sunPathRotation * 0.01745329251994),  cos(sunPathRotation * 0.01745329251994)
	);
#endif

const float lavaOverlayResolution                     = 24.0;

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

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).

float interpolateSmooth1(float x) { return x * x * (3.0 - 2.0 * x); }
vec3  interpolateSmooth3(vec3  v) { return v * v * (3.0 - 2.0 * v); }

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
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

#if defined(FANCY_STARS) || defined(GALAXIES)
	//uses additive blending, so no alpha returned.
	vec3 drawStars(inout Position pos) {
		float space = 4.0 / pos.spaceFactor;
		if (pos.playerNorm.y > 0.0 && (night > 0.001 || space < 0.999) && rainStrength * space < 0.999) {
			vec2 dailyOffset = texture2D(noisetex, (floor(vec2(worldDay, worldDay * invNoiseRes)) + 0.5) * invNoiseRes).rg;
			//vec2 dailyOffset = texelFetch2D(noisetex, ivec2(worldDay, worldDay * invNoiseRes), 0).rg;

			float exclusion = interpolateSmooth1(clamp(acos(-pos.sunDot) * 8.0 - EXCLUSION_RADIUS, 0.0, 1.0)); //darken things around the moon

			vec3 starPos3D = pos.playerNorm;
			starPos3D.yz *= starRotation; //match sunPathRotation
			vec2 starPos = starPos3D.xz / sqrt(starPos3D.y + 1.0); //divide sky up into cells. each cell will have a star in it, though most stars won't actually render
			starPos *= 64.0; //main scaling factor
			starPos.x += worldTime * 0.015625; //gives the appearance of stars rotating like the sun/moon. Not actual rotation, but follows where the moon goes fairly closely

			vec3 result = vec3(0.0);

			#ifdef GALAXIES
				float noise = 0.0; //noise maps for galaxies
				vec2 noisePos = starPos * 0.03125 * invNoiseRes + dailyOffset; //galaxy scaling factor
				noise += texture2D(noisetex, noisePos        ).r * 0.6;
				noise += texture2D(noisetex, noisePos * 2.0  ).r * 0.36;
				noise += texture2D(noisetex, noisePos * 4.0  ).r * 0.216;
				noise += texture2D(noisetex, noisePos * 8.0  ).r * 0.1296;
				noise += texture2D(noisetex, noisePos * 16.0 ).r * 0.07776;
				noise += texture2D(noisetex, noisePos * 32.0 ).r * 0.046656;
				noise += texture2D(noisetex, noisePos * 64.0 ).r * 0.0279936;
				noise += texture2D(noisetex, noisePos * 128.0).r * 0.01679616;
				noise += texture2D(noisetex, noisePos * 256.0).r * 0.010077696;
				noise *= 0.6780553935455204; //1.0 / (0.6 + 0.36 + ... + 0.010077696)
				float biasedNoise = square(max(noise * 3.0 - 1.5, 0.3));

				float colorNoise = 0.0;
				colorNoise += texture2D(noisetex, -noisePos * 2.0).r * 0.5;
				colorNoise += texture2D(noisetex, -noisePos * 4.0).r * 0.25;
				colorNoise += texture2D(noisetex, -noisePos * 8.0).r * 0.125;

				//colorize galaxies with randomized hue
				//also reduce brightness near the moon, and when it's not quite dark enough yet.
				result += mix(hue(colorNoise) * 0.25, vec3(0.25), min(biasedNoise + 0.2, 1.0)) * (biasedNoise - 0.09) * clamp(max(adjustedTime - 7.8, 1.0 - space * 12.0), 0.0, 1.0) * exclusion;
			#endif

			#ifdef FANCY_STARS
				vec3 random = texture2D(noisetex, (floor(starPos + dailyOffset * noiseTextureResolution) + 0.5) * invNoiseRes).rgb;
				//vec3 random = texelFetch2D(noisetex, ivec2(mod(floor(starPos) + dailyOffset * noiseTextureResolution, noiseTextureResolution)), 0).rgb; //rg = star position within cell, b = color/size data (red stars are smaller/dimmer, blue stars are bigger/brighter)
				random.rg = random.rg * 0.7 + 0.15; //fix stars being chopped in half because their position was on the border of a cell
				float dist = distance(fract(starPos), random.rg) * (2.0 - random.b) * 5.0; //distance from center of star, with scaling factor based on color of star. 5.0 is star scaling factor; bigger values = smaller stars.
				dist *= length(gl_FragCoord.xy * vec2(pixelSizeX, pixelSizeY) - 0.5) * 2.0 + 1.0; //compensate for projection effects. 2.0 is scaling factor; increase it if stars on the edge of your screen are bigger than stars in the center
				dist = 1.0 - dist; //positive in center of star, negative outside the star.

				#ifdef GALAXIES
				if (dist > 0.0 && 1.0 - random.b < min(biasedNoise, exclusion)) { //pixel is part of star, and is bright enough for its noise value
					random.b = (random.b + biasedNoise - 1.0) / biasedNoise; //scale value based on threshold (determined by galaxy density)
				#else
				if (dist > 0.0 && 1.0 - random.b < min(0.1, exclusion)) { //pixel is part of star, 1/10'th of the stars generated will actually render.
					random.b = random.b * 10.0 - 9.0; //scale value based on threshold (1/20'th in this case)
				#endif
					vec3 starColor = mix(vec3(0.5), vec3(0.25, 0.5, 1.0), random.b); //blue or white, red dwarfs aren't visible to the naked eye.
					starColor = mix(starColor, vec3(1.0), dist * dist * 0.5 * random.b) * dist * dist; //whitest and brightest in the center
					starColor *= clamp(random.b * random.b * 1.5 + max(adjustedTime - 8.5, 1.0 - space * 16.0), 0.0, 1.0); //fading animation at sunset, blue stars appear sooner and disappear later
					starColor *= random.b * 0.75 + 0.25; //white stars are darker
					#ifdef GALAXIES
						starColor *= (1.0 - noise * 0.75); //stand out less where galaxies are already as bright as the stars
					#endif
					result += starColor;
				}
			#endif

			return result * (1.0 - max(rainStrength, wetness) * space) * (1.0 - fogify(pos.playerNorm.y / space, 0.0625)); //reduce brightness when raining and near the horizon
		}
		return vec3(0.0);
	}
#endif

vec3 calcSkyColor(inout Position pos) {
	float upDot = pos.playerNorm.y * pos.spaceFactor * 0.5; //not much, what's up with you?
	float space = 4.0 / pos.spaceFactor;
	bool top = upDot > 0.0;
	float sunDot = pos.sunDot * 0.5 + 0.5;
	float rainCoefficient = max(rainStrength, wetness);
	vec3 color;
	vec3 skyclr = skyColor;
	skyclr.rg = mix(skyclr.bb, skyclr.rg, OVERWORLD_SKY_SATURATION_BOOST);
	skyclr = mix(skyclr, fogColor * 0.65, rainCoefficient) * space;
	vec3 fogclr = fogColor;
	fogclr.rg = mix(fogclr.bb, fogclr.rg, OVERWORLD_FOG_SATURATION_BOOST);
	fogclr *= (1.0 - rainCoefficient * 0.25) * (1.0 - nightVision * night * 0.75);

	#ifdef RAINBOWS
		float rainbowStrength = (wetness - rainStrength) * day * 0.25;
		float rainbowHue = (sunDot - rainbowPosition) * rainbowThinness;
		if (rainbowStrength > 0.0 && rainbowHue > 0.0 && rainbowHue < 1.0) {
			rainbowHue *= 6.0;
			vec3 rainbowColor = clamp(vec3(1.5, 2.0, 1.5) - abs(rainbowHue - vec3(1.5, 3.0, 4.5)), 0.0, 1.0) * rainbowStrength;
			skyclr += rainbowColor * space * space;
			fogclr += rainbowColor;
		}
	#endif

	if (top) {
		color = skyclr + nightSkyColor * (1.0 - day) * (1.0 - rainStrength) * space; //avoid pitch black sky at night
		if (day > 0.001) color = mix(color, sunGlowColor,  0.75 / ((1.0 - sunDot) * 16.0 + 1.0) * day   * (1.0 - rainStrength * 0.75) * space); //make the sun illuminate the sky around it
		else             color = mix(color, moonGlowColor, 0.75 / (       sunDot  * 16.0 + 1.0) * night * (1.0 - rainStrength       ) * space * phase); //make the moon illuminate the sky around it
	}
	else color = fogclr;

	if (sunset > 0.001 && rainCoefficient < 0.999) {
		vec3 sunsetColor = interpolateSmooth3(clamp(sunsetColorForSky - adjustedTime + upDot + sunDot * 0.2 * (1.0 - night), 0.0, 1.0)); //main sunset gradient
		sunsetColor = mix(fogclr, sunsetColor, (sunDot * 0.5 + 0.5) * sunset * (1.0 - rainCoefficient)); //fade in at sunset and out when not looking at the sun
		color = mix(color, sunsetColor, fogify(upDot, OVERWORLD_HORIZON_HEIGHT)); //mix with final color based on how close we are to the horizon
	}
	else if (top) color = mix(color, fogclr, fogify(upDot, OVERWORLD_HORIZON_HEIGHT));

	#if defined(FANCY_STARS) || defined(GALAXIES)
		color += drawStars(pos);
	#endif

	color += fract(dot(gl_FragCoord.xy, vec2(0.25, 0.5))) * 0.00390625; //dither

	return color;
}

//checks a few conditions before actually calculating the sky color.
vec3 checkSkyColor(inout Position pos) {
	if (starData.a > 0.5) {
		#ifdef FANCY_STARS
			return vec3(0.0);
		#else
			#ifdef INFINITE_OCEANS
				return starData.rgb * (1.0 - fogify(pos.playerNorm.y * pos.spaceFactor, 0.25)); //apply fog to stars near the horizon
			#else
				return starData.rgb;
			#endif
		#endif
	}

	return calcSkyColor(pos);
}

void main() {
	Position pos;
	vec2 tc = gl_FragCoord.xy * vec2(pixelSizeX, pixelSizeY);
	vec4 tmp = gbufferProjectionInverse * vec4(tc * 2.0 - 1.0, 1.0, 1.0);
	pos.viewNorm = normalize(tmp.xyz);
	pos.playerNorm = mat3(gbufferModelViewInverse) * pos.viewNorm;
	pos.sunDot = dot(pos.viewNorm, sunPosNorm);
	pos.spaceFactor = square(max(actualCameraPosition.y, (bedrockLevel + heightLimit)) * (1.0 / heightLimit) + 1.0);

	vec3 color = checkSkyColor(pos);

/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(color, 1.0); //gcolor
}