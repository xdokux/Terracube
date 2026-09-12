// AETHER — user settings & option macros
#ifndef SETTINGS_GLSL
#define SETTINGS_GLSL

#define SKY_DENSITY 1.0        // [0.5 0.75 1.0 1.25 1.5 2.0]
#define HAZE_HUMIDITY 0.6      // [0.0 0.2 0.4 0.6 0.8 1.0]
#define CLOUDS_ENABLED         // Volumetric clouds toggle
#define CLOUD_COVERAGE 0.45    // [0.2 0.3 0.45 0.6 0.75 0.9]
#define CLOUD_QUALITY 1        // [0 1 2] Low/High/Ultra march steps
#define FOG_STORM_BOOST 1.0    // [0.5 1.0 1.5 2.0]

#define SUN_INTENSITY 1.0      // [0.6 0.8 1.0 1.2 1.5]
#define LABPBR                 // labPBR resource pack support (auto-detects missing textures)
#define POM                    // Parallax occlusion mapping from heightmaps
#define POM_DEPTH 0.10         // [0.05 0.10 0.15 0.25]
#define POM_SAMPLES 16         // [8 16 32]
#define POM_DISTANCE 24.0      // [12.0 24.0 48.0]
#define GI_SAMPLES 6           // [4 6 8 12]
#define GI_DISTANCE 48.0       // [32.0 48.0 96.0]
#define SSGI_ENABLED           // Screen-space GI toggle
#define GI_STRENGTH 1.0        // [0.5 0.75 1.0 1.25 1.5]
#define SSAO_STRENGTH 1.0      // [0.0 0.5 1.0 1.5]
#define CONTACT_SHADOWS        // Screen-space contact shadows
#define LIGHTNING_FLASH        // World-illuminating lightning

#define EXPOSURE_BIAS 0.0      // [-1.0 -0.5 0.0 0.5 1.0]
#define AUTO_EXPOSURE          // Dynamic eye adaptation
#define GLARE_STRENGTH 0.7     // [0.0 0.35 0.7 1.0 1.5]
#define FILM_GRAIN 0.03        // [0.0 0.015 0.03 0.05 0.08]
#define CHROM_ABERRATION 0.5   // [0.0 0.25 0.5 0.75 1.0]

#define WATER_ABSORPTION 1.0   // [0.5 0.75 1.0 1.5 2.0]
#define CAUSTICS_ENABLED       // Animated water caustics
#define WATER_REFLECTIONS      // Screen-space water reflections
#define SHADOW_QUALITY 2       // [1 2 3] PCF taps tier

const int   shadowMapResolution   = 2048;   // [1024 2048 4096]
const float shadowDistance        = 120.0;  // [96.0 120.0 160.0 256.0]
const float sunPathRotation       = -35.0;
const float ambientOcclusionLevel = 0.7;

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16;
const int colortex2Format = RGBA8;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
const int colortex5Format = RGBA16F;
*/
const bool colortex4Clear = false;
const bool colortex0Clear = true;
const float eyeBrightnessHalflife = 4.0;

#endif
