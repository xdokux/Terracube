/*
    settings.glsl
    ---------------------------------------------------------------
    Every quality knob in the pack lives here, in one place, so you
    never have to go hunting through six files to find a #define.

    The "// [a b c] comment" syntax after a #define is the standard
    OptiFine/Iris auto-slider format: Iris scans for this pattern
    and automatically builds a dropdown/slider in the in-game
    Shader Options screen. You do NOT need to register these by
    hand anywhere else.

    Values here are the defaults used when no profile is selected.
    The profiles in shaders.properties (igpu / normal) OVERRIDE
    these at load time - see shaders.properties for what each
    profile actually sets.
    ---------------------------------------------------------------
*/
#ifndef SETTINGS_GLSL
#define SETTINGS_GLSL


//////////////////////////////// SHADOWS ////////////////////////////////

// Shadow map resolution. This is a second full geometry pass of the
// scene, so on integrated GPUs this matters more than almost any
// other setting - it's draw-call/geometry bound, not just fragment cost.
// Cost: Low (512) / Medium (1024) / High (2048)
#define SHADOW_RES 1024 // [512 1024 2048]

// Shadow render distance in blocks. Independent of your normal render
// distance - shadows this far out are rarely visible anyway.
// Cost: scales roughly linearly
#define SHADOW_DISTANCE 96.0 // [48.0 64.0 96.0 128.0 160.0]

// Number of PCF (Percentage Closer Filtering) taps used to soften
// shadow edges. 1 = hard single-sample shadow (cheapest, can look
// blocky/aliased). 4 = soft shadow edges.
// UHD 630 hard cap: keep this at 1 on the igpu profile. Each extra
// tap is a full extra shadow-map texture fetch per fragment, and
// iGPUs are fill-rate/bandwidth limited, not compute limited.
// Cost: Low(1) / Medium(2) / High(4)
#define PCF_TAPS 2 // [1 2 4]

//////////////////////////////// GOD RAYS ////////////////////////////////

// Volumetric light shafts, raymarched in screen space toward the sun/
// moon and modulated by shadow visibility at each step.
// Cost: Medium-High. This is the single most expensive Tier-2 effect
// in the pack - disable first on weak hardware.
#define GODRAYS 1 // [0 1]

// Raymarch step count for god rays. Directly multiplies cost - each
// step is a shadow-map sample plus a scene-depth comparison.
// UHD 630 hard cap: 6. Integrated GPUs have essentially no headroom
// for iteration-heavy loops; this is the first thing to cut further
// if igpu framerates still aren't hitting 30fps.
#define GODRAY_STEPS 12 // [6 8 12 16 24]

// God rays use interleaved-gradient-noise dithering to jitter each
// pixel's raymarch start offset. This hides banding between visible
// ray steps WITHOUT needing more steps - much cheaper than raising
// GODRAY_STEPS, and it's why GODRAY_STEPS can stay low even at
// full resolution. (A true quarter-resolution offscreen buffer with
// bilateral upsampling would be a further win and is a reasonable
// v2 addition - see CHANGELOG - but it needs its own sized render
// target and a second composite pass to upsample, which is more
// pipeline complexity than this first pass is aiming for.)

//////////////////////////////// WATER ////////////////////////////////

// Wave animation is done per-VERTEX (in gbuffers_water.vsh), not
// per-fragment, deliberately - it's effectively free on any GPU
// including the UHD 630 since it's evaluated once per vertex on a
// low-poly water plane, not once per pixel.
#define WATER_WAVE_HEIGHT 0.10
#define WATER_WAVE_SPEED 0.6

// Underwater fog density. Cheap - just a per-fragment exponential
// fog term, no extra passes.
#define UNDERWATER_FOG_DENSITY 0.10

//////////////////////////////// FOG / SKY ////////////////////////////////

// Overworld fog is blended a bit earlier than vanilla so distant
// terrain pop-in is less jarring - purely a per-fragment lerp, free.
#define FOG_START_MULT 0.75

//////////////////////////////// TONEMAP ////////////////////////////////

// Simple filmic-ish tonemap curve strength. 0 = off (linear-ish/vanilla
// look), 1 = full curve. This is a single cheap per-pixel operation in
// the final pass, negligible cost on any hardware.
#define TONEMAP_STRENGTH 0.85 // [0.0 0.25 0.5 0.75 0.85 1.0]

// Saturation boost applied alongside the tonemap curve, also
// essentially free.
#define SATURATION 1.08

//////////////////////////////// PLATFORM GUARD ////////////////////////////////

// Defined by shaders.properties on the igpu profile only. Other files
// check #ifdef IGPU_PROFILE to hard-disable features entirely at
// compile time (not just branch around them at runtime) - Iris/
// OptiFine packs recompile per-option anyway, so an #ifdef costs
// nothing and a runtime "if (godrays_enabled)" branch would still
// pay for shader complexity/register pressure even when off.
// #define IGPU_PROFILE

#endif // SETTINGS_GLSL
