// ============================================================
//  CinematicVanilla V2 - settings.glsl
//  All user-facing toggles. Profiles (LOW/MEDIUM/HIGH) in
//  shaders.properties override these defaults at load time.
// ============================================================

/// ─── Performance Preset ─────────────────────────────────────────────────────
// profile is set by shaders.properties; individual toggles below can be
// overridden by the user in the shader menu.

/// ─── Post Processing ────────────────────────────────────────────────────────
#define OUTLINES 2               // Block outlines. 0=off 1=classic 2=dungeons [0 1 2]
#define OUTLINE_BRIGHTNESS 0.80  // [-1.00 -0.75 -0.50 -0.25 0.00 0.25 0.50 0.75 1.00]
#define OUTLINE_PIXEL_SIZE 1     // [1 2 4]

#define ANTI_ALIASING 2          // 0=off 1=FXAA 2=TAA 3=both [0 1 2 3]
// #define SHARPEN_FILTER

/// ─── Bloom ───────────────────────────────────────────────────────────────────
#define BLOOM                    // Toggle: bloom glow
#define BLOOM_STRENGTH 0.90      // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define BLOOM_RADIUS 4           // Blur radius in passes. High = softer, costs perf. [2 4 6 8]

/// ─── Depth of Field ─────────────────────────────────────────────────────────
// #define DOF                   // Toggle: cinematic depth of field
#define DOF_STRENGTH 2           // [1 2 3 4 5]
#define DOF_FOCAL_DIST 8.0       // Focus distance in blocks [2.0 4.0 8.0 16.0 32.0]

/// ─── Camera ─────────────────────────────────────────────────────────────────
// #define CHROMATIC_ABERRATION
#define ABERRATION_PIXEL_SIZE 2  // [1 2 4]
// #define VIGNETTE
#define VIGNETTE_STRENGTH 0.80   // [0.00 0.25 0.50 0.75 1.00 1.25 1.50]
// #define MOTION_BLUR
#define MOTION_BLUR_STRENGTH 0.75 // [0.25 0.50 0.75 1.00]

/// ─── Lens Flare ─────────────────────────────────────────────────────────────
#define LENS_FLARE
#define LENS_FLARE_STRENGTH 0.85 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50]

/// ─── Tonemapping ────────────────────────────────────────────────────────────
#define CONTRAST   1.06          // [0.80 0.90 1.00 1.05 1.06 1.10 1.15 1.20]
#define SATURATION 0.93          // [0.70 0.80 0.90 0.93 1.00 1.10 1.20]
#define WHITE_POINT 2.0          // [1.0 1.5 2.0 2.5 3.0]
#define SHOULDER_STRENGTH 0.05   // [0.00 0.05 0.10 0.15 0.20]
// #define AUTO_EXPOSURE
#define EXPOSURE 1.00            // [0.50 0.75 1.00 1.25 1.50]

#define TINT_R 255
#define TINT_G 255
#define TINT_B 255

/// ─── Lighting ───────────────────────────────────────────────────────────────
#define SHADOW_MAPPING
#define SHADOW_FILTER            // Soft shadows (PCSS-style noise)
#define SHADOW_COLOR             // Transparent-object shadow tinting
#define SHADOW_RESOLUTION 2048   // [1024 2048 4096]  (profile overrides)

// Contact shadows: cheap screen-space rim darkening at geometry edges
// #define CONTACT_SHADOWS        // Toggle
#define CONTACT_SHADOW_STEPS 8   // [4 8 12 16]
#define CONTACT_SHADOW_RADIUS 0.4 // Screen radius [0.1 0.2 0.4 0.6]

#define ENTITY_SHADOWS
#define BLOCK_ENTITY_SHADOWS

const float sunPathRotation = 30.0; // [-60.0 -45.0 -30.0 -15.0 0.0 15.0 30.0 45.0 60.0]

#define UNDERWATER_CAUSTICS 1    // [0 1 2]
#define SSAO                     // Screen-space ambient occlusion
#define AMBIENT_LIGHTING 0.06    // [0.00 0.03 0.06 0.10 0.15 0.20]

/// ─── Global Illumination / Reflections ──────────────────────────────────────
// #define SSGI
#define SSR                      // Screen-space reflections
#define RAYTRACER_STEPS 20       // [16 20 24 32]
#define RAYTRACER_BISTEPS 2      // [0 2 4 6]
// #define ROUGH_REFLECTIONS
#define PREVIOUS_FRAME

/// ─── God Rays ────────────────────────────────────────────────────────────────
#define GOD_RAYS                 // Toggle: sun/moon volumetric shafts
#define GOD_RAY_STEPS 8          // [4 8 12 16]  (LOW uses 0 = disabled)
#define GOD_RAY_STRENGTH 0.55    // [0.10 0.25 0.55 0.75 1.00]

/// ─── Atmospherics ───────────────────────────────────────────────────────────
#define SUN_MOON_TYPE 0          // [0 1 2]
#define SUN_MOON_INTENSITY 4     // [0 1 2 3 4 5 6]

#define VOLUMETRIC_LIGHTING
#define VOLUMETRIC_LIGHTING_STRENGTH 0.50 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70]

/// ─── Cinematic Fog ──────────────────────────────────────────────────────────
#define CINEMATIC_FOG            // Toggle: distance + height based fog
#define BORDER_FOG
#define GROUND_FOG_STRENGTH 0.55 // [0.00 0.10 0.25 0.40 0.55 0.70 0.85 1.00]
#define SKYBOX_BRIGHTNESS 1.00   // [0.50 0.75 1.00 1.25 1.50]

/// ─── Clouds ─────────────────────────────────────────────────────────────────
#define CLOUD_TYPE 2             // 0=off 1=vanilla 2=volumetric [0 1 2]
#define DOUBLE_LAYERED_CLOUDS
#define DYNAMIC_CLOUDS
#define FADE_SPEED 0.20          // [0.05 0.10 0.20 0.30 0.40]
#define SECOND_CLOUD_HEIGHT 128.0 // [64.0 96.0 128.0 160.0 192.0 256.0]
#define VOLUMETRIC_CLOUD_STEPS 16 // [8 16 32 64]   (HIGH = 32)
#define VOLUMETRIC_CLOUD_DEPTH 8.0 // [4.0 6.0 8.0 10.0 12.0]
#define SKYBOX_CLOUD_STEPS 16    // [8 16 32 64]
#define SKYBOX_CLOUD_DEPTH 0.08  // [0.02 0.04 0.08 0.12 0.16]

/// ─── Water ──────────────────────────────────────────────────────────────────
#define WATER_WAVE_QUALITY 1     // 0=flat 1=medium 2=high [0 1 2]
#define WATER_DEPTH_TINT         // Toggle: depth-based color absorption
#define WATER_DEPTH_COLOR vec3(0.04, 0.20, 0.30) // Shallow → deep color
#define WATER_DEPTH_SCALE 0.20   // Absorption per meter [0.05 0.10 0.20 0.35]
#define UNDERWATER_BLUR          // Toggle: underwater distortion effect

/// ─── Wet Surfaces ───────────────────────────────────────────────────────────
#define WET_SURFACES             // Toggle: rain darkens & adds specularity
#define WET_PUDDLES              // Toggle: animated puddle ripples in rain

/// ─── Wind ───────────────────────────────────────────────────────────────────
#define WIND_QUALITY 1           // 0=off 1=simple 2=gusting [0 1 2]
#define WIND_SPEED 1.0           // [0.0 0.5 1.0 1.5 2.0]
#define WIND_FREQUENCY 1.0       // [0.5 1.0 1.5 2.0]
#define CURRENT_SPEED 1.0
#define CURRENT_FREQUENCY 0.5

// ============================================================
//  CinematicVanilla V3 — New Settings
// ============================================================

/// ─── Seasonal Preset ────────────────────────────────────────────────────────
// Changes the color grade to match a season's mood.
// None = classic CinematicVanilla look
#define SEASONAL_PRESET 0        // 0=None 1=Summer 2=Autumn 3=Winter 4=Spring [0 1 2 3 4]

/// ─── Poster Mode ────────────────────────────────────────────────────────────
// Activates an aggressive cinematic grade designed for screenshots.
// Stronger teal-orange split tone, boosted contrast & saturation,
// cinematic letterbox bars, and enhanced film grain.
// Toggle ON/OFF in shader menu. Does NOT affect gameplay performance.
// #define POSTER_MODE

/// ─── Film Halation ──────────────────────────────────────────────────────────
// Warm red-orange glow on bright highlights — vintage film emulsion effect.
// Already ON in Poster Mode. Can be enabled separately here.
// #define FILM_HALATION

/// ─── Letterbox (Poster Mode bars) ───────────────────────────────────────────
#define LETTERBOX_STRENGTH 0.10  // Height of bars as fraction of screen [0.05 0.08 0.10 0.12 0.15 0.20]
