/*
    common.glsl
    ---------------------------------------------------------------
    Small shared helpers with no dependencies on other lib/ files.
    Kept deliberately tiny - every function here is used in more
    than one shader stage, which is the only reason it's not just
    inlined.
    ---------------------------------------------------------------
*/
#ifndef COMMON_GLSL
#define COMMON_GLSL


const float PI = 3.14159265359;

// Standard exponential-squared fog, same shape vanilla Minecraft uses,
// so fog blends match the vanilla horizon instead of looking like a
// shader-pack "wall". One exp2() call - trivial cost.
float expFog(float dist, float fogStart, float fogEnd) {
    float f = clamp((dist - fogStart) / (fogEnd - fogStart), 0.0, 1.0);
    return f * f * (3.0 - 2.0 * f); // smoothstep-shaped falloff
}

// Cheap underwater fog term, exponential rather than linear so it
// thickens quickly near the camera the way real water does.
float underwaterFog(float dist, float density) {
    return 1.0 - exp(-dist * density);
}

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Cheap saturation adjustment around luminance - single lerp, no
// matrix math, negligible cost even on igpu.
vec3 adjustSaturation(vec3 color, float amount) {
    float l = luminance(color);
    return mix(vec3(l), color, amount);
}

#endif // COMMON_GLSL
