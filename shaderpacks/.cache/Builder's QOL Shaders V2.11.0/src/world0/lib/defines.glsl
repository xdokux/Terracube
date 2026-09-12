#include "/lib/defines.glsl"

#define CLOUD_DENSITY_AVERAGE 0.0 //Average cloud density. Higher value means more clouds [-2.0 -1.9 -1.8 -1.7 -1.6 -1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.4 -0.3 -0.2 -0.1 0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define CLOUD_DENSITY_VARIANCE 1.5 //How far above or below the average cloud density will go [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define CLOUD_NORMALS //Dynamically light clouds based on weather they're facing towards or away from the sun. Mild performance impact!
//#define CUSTOM_SKY_FIX //Disables sun fadeout near the horizon when infinite oceans are enabled. Enable this if your resource pack's custom skys turn black near the horizon.
#define DESATURATE_NIGHT 0.50 //Amount to desaturate the world at night [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define DESATURATE_RAIN 0.50 //Amount to desaturate the world when raining [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define END_PORTAL_BACKGROUND_OVERWORLD 2 //1: Use overworld fog color. 2: Use end background. [1 2]
#define END_PORTAL_CLOUDS_OVERWORLD 2 //0: No clouds. 1: Use overworld clouds. 2: Use void clouds. [0 1 2]
#define END_PORTAL_EFFECTS_OVERWORLD //Enables fancy effects for end portals
#define END_PORTAL_FOREGROUND_OVERWORLD 2 //0: No foreground image. 1: Use overworld screenshot. 2: Use end island screenshot. [0 1 2]
#define EXCLUSION_RADIUS 1.0 //Radius around the moon at which fancy stars/galaxies stop rendering [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define EYE_ADJUST_OVERWORLD_DARK 3.0 //Brightness multiplier for the whole screen when standing in darkness in the overworld [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define EYE_ADJUST_OVERWORLD_LIGHT 1.5 //Brightness multiplier for the whole screen when standing in bright light in the overworld [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define FANCY_STARS //Improved stars in the overworld
#define FOG_DENSITY_MULTIPLIER_OVERWORLD 1.00 //How much overall fog there is in the overworld. [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00 2.50 3.00 3.50 4.00 4.50 5.00 6.00 7.00 8.00 9.00 10.00]
#define FOG_ENABLED_OVERWORLD //Enables fog in the overworld. It is recommended to have this enabled if you also have infinite oceans enabled!
#define FOG_HEIGHT_MULTIPLIER_OVERWORLD 32.0 //Controls how much denser fog is at lower altitudes [16.0 24.0 32.0 48.0 64.0 96.0 128.0 192.0 256.0 384.0 512.0 768.0 1024.0]
#define GALAXIES //Galaxies visible at night in the overworld, with even more stars inside them
#define HARDCORE_DARKNESS 0 //0 (Off): Normal visibility at night. 1 (On): Complete darkness at night. 2 (Moon phase) Nighttime brightness is determined by the current phase of the moon. [0 1 2]
#define INFINITE_OCEANS //Simulates water out to the horizon instead of just your render distance.
#define OVERWORLD_FOG_SATURATION_BOOST 1.25 //Makes the horizon blue-er [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50]
#define OVERWORLD_HORIZON_HEIGHT 0.2 //How far above the horizon the fog color will be applied [0.001 0.002 0.003 0.004 0.005 0.0075 0.01 0.02 0.03 0.04 0.05 0.075 0.1 0.2 0.3 0.4 0.5 0.75 1.0]
#define OVERWORLD_SKY_SATURATION_BOOST 1.50 //Makes the sky blue-er [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50]
#define RAIN_BLUR 10 //Blurs the world while raining [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define RAINBOWS //If enabled, rainbows will appear when the weather changes from rainy to clear
#define SEA_LEVEL 63 //Sea level for infinite oceans. Change this if you use custom worldgen. [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256]
#define SHADE_STRENGTH 0.35 //How dark surfaces that are facing away from the sun are [0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.50]
#define SUN_POSITION_FIX //Enable this if the horizon "splits" at sunset when rapidly rotating your camera.
#define WAVING_RAIN //Makes rain not directly vertical by applying "wind" to it.
#define WET_DIRT //Hydrated hummus. Soggy soil. Drenched dirt. I can't think of a good name for this config option, but it makes dirt darker during rain to simulate being wet.

#define END_PORTAL_BACKGROUND END_PORTAL_BACKGROUND_OVERWORLD
#define END_PORTAL_CLOUDS END_PORTAL_CLOUDS_OVERWORLD
#define END_PORTAL_EFFECTS END_PORTAL_EFFECTS_OVERWORLD
#define END_PORTAL_FOREGROUND END_PORTAL_FOREGROUND_OVERWORLD