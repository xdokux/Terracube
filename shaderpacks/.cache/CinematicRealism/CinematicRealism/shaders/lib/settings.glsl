/*
    settings.glsl - every quality/style knob, in one place.
    "// [values]" comments are the OptiFine/Iris auto-slider syntax -
    Iris builds the in-game options menu from these automatically.
*/
#ifndef SETTINGS_GLSL
#define SETTINGS_GLSL

//////////////////////////// SHADOWS ////////////////////////////
#define SHADOW_RES 2048 // [1024 2048 4096]
#define SHADOW_DISTANCE 140.0 // [80.0 110.0 140.0 180.0]
#define PCF_TAPS 4 // [1 2 4 8]

// Distortion factor for the pseudo-cascade shadow warp - higher
// values pack more resolution near the camera at the cost of more
// distortion on distant shadows. This is the real technique behind
// "cascaded-looking" shadows in a single-shadow-map pipeline (Iris/
// OptiFine don't support true multi-map CSM).
#define SHADOW_DISTORTION 0.85 // [0.6 0.75 0.85 0.95]

//////////////////////////// LIGHTING ////////////////////////////
// Minimum ambient light floor. This exists specifically so caves and
// unlit night-time terrain never render pure black - a common bug in
// homemade shaders that forget vanilla's own minimum light level.
#define MIN_AMBIENT 0.045 // [0.02 0.03 0.045 0.06]

// Warm-light tint strength and per-block-type color hinting for
// torches/lava/redstone (see lib/lighting.glsl for the honest caveat
// on why this isn't full per-light-source RGB lighting).
#define COLORED_LIGHT_HINTS 1 // [0 1]
#define BLOCKLIGHT_WARMTH 0.35

//////////////////////////// SKY / SUN ////////////////////////////
#define GOLDEN_HOUR_STRENGTH 1.0 // [0.5 0.75 1.0 1.25]
#define SUN_GLOW_SIZE 0.06 // [0.04 0.06 0.08 0.1]

//////////////////////////// CLOUDS ////////////////////////////
#define CLOUDS 1 // [0 1]
#define CLOUD_HEIGHT 190.0
#define CLOUD_SPEED 0.35
#define CLOUD_COVERAGE 0.55 // [0.35 0.45 0.55 0.65]

//////////////////////////// FOG ////////////////////////////
#define HEIGHT_FOG 1 // [0 1]
#define HEIGHT_FOG_DENSITY 0.018 // [0.008 0.013 0.018 0.026]
#define HEIGHT_FOG_FALLOFF_Y 80.0

//////////////////////////// BLOOM ////////////////////////////
#define BLOOM 1 // [0 1]
#define BLOOM_THRESHOLD 0.85 // [0.6 0.75 0.85 1.0]
#define BLOOM_INTENSITY 0.30 // [0.15 0.22 0.30 0.4]

//////////////////////////// WATER ////////////////////////////
#define WATER_WAVE_HEIGHT 0.09
#define WATER_WAVE_SPEED 0.55
#define RAIN_RIPPLES 1 // [0 1]
#define PUDDLES 1 // [0 1]
#define PUDDLE_COVERAGE 0.6 // [0.3 0.45 0.6 0.8]

//////////////////////////// TONEMAP ////////////////////////////
#define TONEMAP_STRENGTH 0.9
#define SATURATION 1.1
#define EXPOSURE 1.05 // [0.85 0.95 1.05 1.2]

#endif // SETTINGS_GLSL
