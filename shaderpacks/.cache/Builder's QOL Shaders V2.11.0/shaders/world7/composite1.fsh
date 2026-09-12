#version 120

#define ALT_GLASS //Uses alternate blending method for stained glass which looks more like real stained glass
#define BLUR_ENABLED //Is blur enabled at all?
#define BRIGHT_WATER //Overrides light levels under water to be higher
#define DOF_STRENGTH 0 //Blurs things that are at a different distance than whatever's in the center of your screen [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define DYNAMIC_LIGHT_VIGNETTE 50 //Reduces the brightness of dynamic light around edges the of your screen [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define GLASS_BLUR 8 //Blurs things behind stained glass [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
#define ICE_BLUR 4 //Blurs things behind ice [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define ICE_NORMALS //Distorts things reflected by ice. Has no effect when reflections are disabled!
#define ICE_REFRACT //Distorts things behind ice
#define REFLECT //Reflects the sun/sky onto reflective surfaces. Does not add reflections of terrain!
#define REFRACT_AMOUNT 1.00 //Multiplier for the amount of refraction applied to water [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00 2.50 3.00 3.50 4.00 4.50 5.00]
#define UNDERWATER_BLUR 8 //Blurs the world while underwater [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define UNDERWATER_FOG //Applies fog to water
//#define VANILLA_LIGHTMAP //Uses vanilla light colors instead of custom ones. Requires optifine 1.12.2 HD_U_D1 or later!
#define WATER_BLUR 4 //Blurs things behind water [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define WATER_NORMALS //Distorts things reflected by water. Has no effect when reflections are disabled!
#define WATER_REFRACT //Distorts things behind water

#define FOG_DISTANCE_MULTIPLIER_TF 0.25 //How far away fog starts to appear in the twilight forest [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
#define FOG_ENABLED_TF //Enables fog in the twilight forest
#define TF_HORIZON_HEIGHT 0.05 //How far above the horizon the fog color will be applied [0.001 0.002 0.003 0.004 0.005 0.0075 0.01 0.02 0.03 0.04 0.05 0.075 0.1 0.2 0.3 0.4 0.5 0.75 1.0]

uniform bool isSpectator;
uniform float aspectRatio;
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
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D composite;
uniform sampler2D depthtex0;
uniform sampler2D gaux2;
uniform sampler2D gaux4;
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;

#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
	varying float dofDistance; //Un-projected centerDepthSmooth
#endif
varying float eyeAdjust; //How much brighter to make the world
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
//required on older versions of optifine for its option-parsing logic.
#ifdef BLUR_ENABLED
#endif
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

vec3 calcFogColor(vec3 pos) {
	return mix(skyColor, fogColor, fogify(max(dot(pos, gbufferModelView[1].xyz), 0.0), TF_HORIZON_HEIGHT));
}

vec3 calcUnderwaterFogColor(vec3 color, float dist, float brightness) {
	vec3 absorb = exp2(-dist * waterAbsorbColor);
	vec3 scatter = waterScatterColor * (1.0 - absorb) * brightness;
	return color * absorb + scatter;
}

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

	vec3 oldAux2 = texture2D(gaux2, texcoord).rgb;
	int id = int(oldAux2.b * 10.0 + 0.1);
	vec3 normal = texture2D(gnormal, texcoord).xyz * 2.0 - 1.0;

	Position nearPos = posFromDepthtex(depthtex0);

	#ifdef REFLECT
		float reflective = 0.0;
	#endif

	float blur = 0.0;

	#if defined(BLUR_ENABLED) && DOF_STRENGTH != 0
		blur = interpolateSmooth1(min(abs(nearPos.blockDist - dofDistance) / dofDistance, 1.0)) * float(DOF_STRENGTH);
	#endif

	#if defined(BLUR_ENABLED) && WATER_BLUR != 0
		float waterBlur = float(WATER_BLUR); //slightly more dynamic than other types of blur
	#endif

	if (id == 1) { //water
		#ifdef REFLECT
			reflective = 0.5;
		#endif

		#if defined(WATER_REFRACT) || (defined(WATER_NORMALS) && defined(REFLECT))
			vec3 newPos = nearPos.world;
			ivec2 swizzles;
			float multiplier = 1.0;
			if (abs(normal.y) > 0.1) { //top/bottom surfaces
				if (abs(normal.y) < 0.999) newPos.xz -= normalize(normal.xz) * (frameTimeCounter * 3.0);
				else multiplier = oldAux2.g * 0.75 + 0.25;
				swizzles = ivec2(0, 2);
			}
			else {
				newPos.y += frameTimeCounter * 4.0;
				if (abs(normal.x) < 0.02) swizzles = ivec2(0, 1);
				else swizzles = ivec2(2, 1);
			}

			vec2 offset = waterNoiseLOD(vec2(newPos[swizzles[0]], newPos[swizzles[1]]), nearPos.blockDist) * (multiplier * 0.015625);
			#ifdef WATER_NORMALS
				normal[swizzles[0]] += offset[0] * 4.0;
				normal[swizzles[1]] += offset[1] * 4.0;
			#endif

			#ifdef WATER_REFRACT
				vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio) / max(nearPos.blockDist * 0.0625, 1.0);
				vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
				if (dot(normal, newnormal) > 0.9) { //don't offset on the edges of water
					tc = newtc;
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
			if (id == 3) { //normal ice
				vec2 coord = (abs(normal.y) < 0.001 ? vec2(nearPos.world.x + nearPos.world.z, nearPos.world.y) : nearPos.world.xz);
				offset = iceNoiseLOD(coord * 256.0, nearPos.blockDist) * 0.0078125;
			}
			else { //held ice
				vec2 coord = gl_FragCoord.xy + 0.5;
				offset = iceNoise(coord * 0.5) * 0.0078125;
			}

			#ifdef ICE_REFRACT
				vec2 newtc = tc + vec2(offset.x, offset.y * aspectRatio);
				vec3 newnormal = texture2D(gnormal, newtc).xyz * 2.0 - 1.0;
				if (dot(normal, newnormal) > 0.9) tc = newtc; //don't offset on the edges of ice
			#endif

			#ifdef ICE_NORMALS
				normal = normalize(normal + offset * 8.0);
			#endif
		#endif
	}

	vec3 aux2 = texture2D(gaux2, tc).rgb;
	if (abs(aux2.b - oldAux2.b) > 0.02) {
		tc = texcoord;
		aux2 = texture2D(gaux2, tc).rgb;
	}

	vec4 c = texture2D(gcolor, tc);
	vec3 color = c.rgb;
	float transparentAlpha = c.a; //using gcolor to store composite's alpha
	vec4 transparent = texture2D(composite, tc); //transparency of closest object to the camera

	#if defined(BLUR_ENABLED) && UNDERWATER_BLUR != 0
		if (isEyeInWater == 1) blur = float(UNDERWATER_BLUR);
	#endif

	if (transparentAlpha > 0.001) {
		#ifdef ALT_GLASS
			if (id == 2) {
				vec3 transColor = transparent.rgb / transparentAlpha;
				color *= transColor * (2.0 - transColor); //min(transColor * 2.0, 1.0); //because the default colors are too dark to be used.

				float skylight = aux2.g;
				float blocklight = aux2.r;
				float heldlight = 0.0;

				color += transColor * calcMainLightColor(blocklight, skylight, heldlight, nearPos) * 0.125 * (1.0 - blindness);
			}
			else {
		#endif
				color = mix(color, transparent.rgb / transparentAlpha, transparentAlpha);
		#ifdef ALT_GLASS
			}
		#endif
	}

	#ifdef REFLECT
		reflective *= aux2.g * aux2.g * (1.0 - blindness);
		vec3 reflectedPos;
		if (isEyeInWater == 0 && reflective > 0.001) { //sky reflections
			vec3 newnormal = mat3(gbufferModelView) * normal;
			reflectedPos = reflect(nearPos.viewNorm, newnormal);
			vec3 skyclr = calcFogColor(reflectedPos);
			float posDot = dot(-nearPos.viewNorm, newnormal);
			color += skyclr * square(square(1.0 - max(posDot, 0.0))) * reflective;
		}
	#endif

	if (id >= 1) { //everything that I've currently assigned effects to so far needs fog to be done in this stage.
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
			#ifdef FOG_ENABLED_TF
				float fogAmount = nearPos.viewDist - 0.2;
				if (fogAmount > 0.0) {
					fogAmount = fogify(fogAmount * exp2(1.5 - nearPos.world.y * 0.015625), FOG_DISTANCE_MULTIPLIER_TF);
					color = mix(calcFogColor(nearPos.viewNorm) * min(max(aux2.g * 2.0, eyeBrightness.y / 120.0), 1.0) * (1.0 - blindness), color, fogAmount);
					#if defined(BLUR_ENABLED) && WATER_BLUR != 0
						waterBlur *= fogAmount;
					#endif
				}
			#endif
		}
	}

	color = min(color, 1.0); //reflections (And possibly other things) can go above maximum brightness

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