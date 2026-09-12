#version 120

//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]

#define FOG_DENSITY_MULTIPLIER_OVERWORLD 1.00 //How much overall fog there is in the overworld. [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00 2.50 3.00 3.50 4.00 4.50 5.00 6.00 7.00 8.00 9.00 10.00]
#define FOG_ENABLED_OVERWORLD //Enables fog in the overworld. It is recommended to have this enabled if you also have infinite oceans enabled!
#define FOG_HEIGHT_MULTIPLIER_OVERWORLD 32.0 //Controls how much denser fog is at lower altitudes [16.0 24.0 32.0 48.0 64.0 96.0 128.0 192.0 256.0 384.0 512.0 768.0 1024.0]
#define OVERWORLD_FOG_SATURATION_BOOST 1.25 //Makes the horizon blue-er [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50]
#define OVERWORLD_HORIZON_HEIGHT 0.2 //How far above the horizon the fog color will be applied [0.001 0.002 0.003 0.004 0.005 0.0075 0.01 0.02 0.03 0.04 0.05 0.075 0.1 0.2 0.3 0.4 0.5 0.75 1.0]
#define OVERWORLD_SKY_SATURATION_BOOST 1.50 //Makes the sky blue-er [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50]
#define RAINBOWS //If enabled, rainbows will appear when the weather changes from rainy to clear
#define SEA_LEVEL 63 //Sea level for infinite oceans. Change this if you use custom worldgen. [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256]

uniform float adjustedTime;
uniform float blindness;
uniform float day;
uniform float far;
uniform float night;
uniform float nightVision;
uniform float rainStrength;
uniform float sunset;
uniform float wetness;
uniform sampler2D texture;
uniform vec3 actualCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunPosNorm;
uniform vec3 upPosNorm;

varying vec2 texcoord;
varying vec3 normal;
varying vec3 vPosPlayer;
varying vec3 vPosView;
varying vec4 tint;

struct Position {
	vec3 view;
	vec3 viewNorm;
	vec3 player;
	vec3 world;
	float blockDist;
	float viewDist;
};

const float lavaOverlayResolution                     = 24.0;

#ifdef CROSS_PROCESS
	const vec3 nightSkyColor = vec3(0.02,  0.025, 0.05); //Added to sky color at night to avoid it being completely black
#else
	const vec3 nightSkyColor = vec3(0.025, 0.025, 0.05); //Added to sky color at night to avoid it being completely black
#endif

const vec3 sunsetColorForSky = vec3(7.2, 6.7, 6.2); //Subtract 6.0 from this to get the color of the horizon at sunset.

const float rainbowPosition =   0.25; //1.0 will be on top of the sun, 0.0 will be on top of the moon.
const float rainbowThinness = -24.0; //Positive numbers will make red be on the inside and blue on the outside.

vec3  interpolateSmooth3(vec3  v) { return v * v * (3.0 - 2.0 * v); }

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
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

void main() {
	vec4 color = texture2D(texture, texcoord) * tint;
	if (color.a < 0.1) discard; //abort early if possible.

	#ifdef FOG_ENABLED_OVERWORLD
		Position pos;
		pos.view = vPosView;
		pos.player = vPosPlayer;
		pos.world = vPosPlayer + actualCameraPosition;
		pos.blockDist = length(pos.view);
		pos.viewDist = pos.blockDist / far;
		pos.viewNorm = pos.view / pos.blockDist;

		color.rgb = mix(calcFogColor(pos.viewNorm), color.rgb, calcFogAmount(pos, pos.viewDist));
	#endif

	color.rgb *= 1.0 - blindness;

/* DRAWBUFFERS:2563 */
	gl_FragData[0] = vec4(normal, 1.0); //gnormal
	gl_FragData[1] = vec4(0.0, 1.0, 0.0, 1.0); //gaux2
	gl_FragData[2] = vec4(1.0, 0.0, 0.0, color.a); //gaux3
	gl_FragData[3] = color; //gcolor
}