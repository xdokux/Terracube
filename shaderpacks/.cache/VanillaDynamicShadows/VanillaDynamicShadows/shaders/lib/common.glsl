#ifndef COMMON_GLSL
#define COMMON_GLSL

float expFog(float dist, float fogStart, float fogEnd) {
    float f = clamp((dist - fogStart) / (fogEnd - fogStart), 0.0, 1.0);
    return f * f * (3.0 - 2.0 * f);
}

#endif // COMMON_GLSL
