#ifndef CINDERLIGHT_SETTINGS_GLSL
#define CINDERLIGHT_SETTINGS_GLSL

#define CINDERLIGHT_VERSION 100

#define SHADOW_QUALITY 1 // [0 1 2] Shadow filtering quality.
#define BLOOM_QUALITY 1 // [0 1 2] Bright-pass bloom sample quality.
#define BLOOM_STRENGTH 0.18 // [0.0 0.12 0.18 0.22 0.28] Bloom intensity.
#define WATER_QUALITY 1 // [0 1 2] Analytic water quality.
#define FOG_DENSITY 1.0 // [0.75 0.85 1.0 1.15 1.3] Atmospheric fog density.
#define CAVE_BRIGHTNESS 1.0 // [0.85 1.0 1.05 1.15] Minimum cave visibility.
#define COLOR_WARMTH 1.0 // [0.8 0.9 1.0 1.05 1.15] Final warm color balance.
#define SATURATION 1.0 // [0.9 0.95 1.0 1.02 1.08] Final saturation.
#define EXPOSURE 1.0 // [0.9 0.95 1.0 1.05 1.1] Final exposure.

#define WAVING_PLANTS
#define WAVING_LEAVES

const int shadowMapResolution = 1536; // [1024 1536 2048]
const float shadowDistance = 96.0; // [64.0 80.0 96.0 112.0 128.0]
const float shadowDistanceRenderMul = 1.0;
const bool shadowtex0Nearest = true;
const float shadowIntervalSize = 2.0;
const float sunPathRotation = 0.0;
const float ambientOcclusionLevel = 0.85;
const float eyeBrightnessHalflife = 7.0;
const float drynessHalflife = 5.0;
const float wetnessHalflife = 45.0;

#endif
