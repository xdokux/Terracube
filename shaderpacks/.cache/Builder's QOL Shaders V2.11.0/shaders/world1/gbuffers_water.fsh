#version 120

#define ALT_GLASS //Uses alternate blending method for stained glass which looks more like real stained glass
#define CLEAR_WATER //Overwrites water texture to be completely transparent
//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DYNAMIC_LIGHT_VIGNETTE 50 //Reduces the brightness of dynamic light around edges the of your screen [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
#define THRESHOLD_ALPHA 0.6 //Anything above this opacity counts as part of the border of stained glass, and will not apply blur/reflection effects [0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95]
//#define VANILLA_LIGHTMAP //Uses vanilla light colors instead of custom ones. Requires optifine 1.12.2 HD_U_D1 or later!

#define DESATURATE_END 0.25 //Amount to desaturate the end dimension [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define FOG_DISTANCE_MULTIPLIER_END 0.25 //How far away fog starts to appear in the end [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
//#define FOG_ENABLED_END //Enables fog in the end

uniform float blindness;
uniform float darknessLightFactor;
uniform float far;
uniform float fogEnd;
uniform float fov;
uniform float nightVision;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform float screenBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform sampler2D lightmap;
uniform sampler2D texture;
uniform vec3 fogColor;
uniform vec3 actualCameraPosition;
#ifdef IS_IRIS
	uniform vec3 eyePosition;
#else
	vec3 eyePosition = actualCameraPosition;
#endif

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

const vec3 ambientLightColor   = vec3(0.1, 0.05, 0.2);
const vec3 ambientVibrantColor = vec3(1.0, 0.75, 1.5);

float square(float x)        { return x * x; } //potentially faster than pow(x, 2.0).

float interpolateSmooth1(float x) { return x * x * (3.0 - 2.0 * x); }

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

vec3 calcMainLightColor(inout float blocklight, inout float heldlight, inout Position pos) {
	#ifdef VANILLA_LIGHTMAP
		vec3 lightclr = texture2D(lightmap, vec2(blocklight, 0.98675)).rgb; //31/32 is the maximum light level in vanilla
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

void main() {
	vec4 color = texture2D(texture, texcoord) * tint;

	int id = int(mcentity);

	#ifdef CLEAR_WATER
		if (id == 1) {
			color.a = 0.0;
		}
		else {
	#endif
		#ifdef ALT_GLASS
			bool applyEffects = true;
			if (id == 2) {
				if (color.a > THRESHOLD_ALPHA) {
					color.a = 1.0; //make borders opaque
					id = 0;
				}
				else {
					applyEffects = false; //don't apply lighting effects to the centers of glass
				}
			}
		#else
			if (id == 2 && color.a > THRESHOLD_ALPHA) id = 0;
		#endif

		#ifdef ALT_GLASS
			if (applyEffects) {
		#endif
				Position pos;
				pos.view = vPosView;
				pos.player = vPosPlayer;
				pos.world = pos.player + actualCameraPosition;
				pos.blockDist = length(vPosView);
				pos.viewDist = pos.blockDist / far;

				float blocklight = lmcoord.x;
				float heldlight = 0.0;

				color.rgb *= calcMainLightColor(blocklight, heldlight, pos);

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
					color.rgb = mix(
						fogColor * (1.0 - nightVision * 0.5),
						color.rgb,
						fogify(pos.blockDist / fogEnd, FOG_DISTANCE_MULTIPLIER_END)
					);
				#endif

				if (blindness > 0.0) color.rgb *= interpolateSmooth1(max(1.0 - pos.blockDist * 0.2, 0.0)) * 0.5 * blindness + (1.0 - blindness);

		#ifdef ALT_GLASS
			}
		#endif
	#ifdef CLEAR_WATER
		}
	#endif

/* DRAWBUFFERS:2563 */
	gl_FragData[0] = vec4(normal, 1.0); //gnormal
	gl_FragData[1] = vec4(lmcoord, id * 0.1, 1.0); //gaux2
	gl_FragData[2] = vec4(1.0, 0.0, 0.0, color.a); //gaux3
	gl_FragData[3] = color; //gcolor
}