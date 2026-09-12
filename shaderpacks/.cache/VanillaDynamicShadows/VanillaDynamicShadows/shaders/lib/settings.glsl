#ifndef SETTINGS_GLSL
#define SETTINGS_GLSL

//////////////////////////// SHADOWS ////////////////////////////

// Tension worth naming: "pixel-perfect" and "fast on a UHD 630" pull
// in opposite directions - shadow resolution is the single biggest
// cost lever on integrated GPUs. 1024 is the tuned-for-UHD-630
// default; raise it if you're on better hardware and want crisper
// far-range edges.
#define SHADOW_RES 1024 // [512 1024 1536 2048]

// Kept modest on purpose: shadow distance and effective resolution
// trade off directly (same texel budget spread over less world space
// = crisper). A tight distance is also more honest about what
// "pixel-perfect" can mean at 1024 - claiming pixel-perfect shadows
// out to 200 blocks on this resolution would just be wrong.
#define SHADOW_DISTANCE 72.0 // [48.0 64.0 72.0 96.0]

// Normal-offset bias, in shadow texels. This is what actually fixes
// jitter/acne, NOT a big depth bias (which causes peter-panning
// instead) and NOT PCF blurring (which fights the "pixel-perfect"
// goal). See lib/shadows.glsl for how it's applied.
#define NORMAL_OFFSET_TEXELS 1.4 // [0.8 1.1 1.4 1.8]

//////////////////////////// GOD RAYS ////////////////////////////

#define GODRAYS 1 // [0 1]

// Hard-capped low on purpose - iteration-heavy loops are close to
// the worst case for a UHD 630's weak parallelism.
#define GODRAY_STEPS 8 // [4 6 8 12]

// How far the raymarch reaches, in blocks. God rays are a near-
// camera effect - marching further just burns steps on a region
// where the effect isn't visible anyway.
#define GODRAY_DISTANCE 40.0 // [24.0 32.0 40.0 56.0]

#define GODRAY_INTENSITY 0.28 // [0.15 0.22 0.28 0.38]

//////////////////////////// LIGHTING ////////////////////////////

// Ambient floor - stops caves/night terrain going pure black. Purely
// a function of vanilla's own sky-light lightmap channel, so it's
// stable regardless of camera angle.
#define MIN_AMBIENT 0.05

#endif // SETTINGS_GLSL
