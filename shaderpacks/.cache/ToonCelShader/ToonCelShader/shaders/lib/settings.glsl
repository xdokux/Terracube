#ifndef SETTINGS_GLSL
#define SETTINGS_GLSL

// Quantized lighting bands - this is THE toon-shading technique:
// instead of a smooth diffuse gradient, light gets snapped into a
// small number of discrete steps, giving the flat "anime/cel" look.
#define LIGHT_BANDS 3 // [2 3 4 5]

// Shadows are hard-edged on purpose here (no PCF softening) - soft
// shadows read as "realistic", hard shadows read as "stylized",
// which is the look this pack is going for.
#define SHADOW_RES 1024 // [512 1024 2048]
#define SHADOW_DISTANCE 100.0

//////////////////////////// OUTLINES ////////////////////////////
// The signature cel-shader feature: screen-space outlines drawn
// wherever depth or normal changes sharply between neighboring
// pixels - i.e. silhouette edges and hard corners.
#define OUTLINES 1 // [0 1]
#define OUTLINE_THICKNESS 1.4 // [1.0 1.4 1.8 2.4]
#define OUTLINE_DEPTH_SENSITIVITY 1.2 // [0.6 1.0 1.2 1.6]
#define OUTLINE_NORMAL_SENSITIVITY 0.4 // [0.2 0.3 0.4 0.6]
#define OUTLINE_COLOR vec3(0.05, 0.05, 0.08)

//////////////////////////// COLOR ////////////////////////////
#define SATURATION 1.35 // [1.1 1.2 1.35 1.5]
#define POSTERIZE_LEVELS 0 // [0 6 8 12]  (0 = off - full posterize can look muddy on busy scenes, off by default)
#define RIM_LIGHT_STRENGTH 0.5 // [0.0 0.3 0.5 0.7]

#endif // SETTINGS_GLSL
