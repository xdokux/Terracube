#ifndef CINDERLIGHT_WORLD_GLSL
#define CINDERLIGHT_WORLD_GLSL

uniform float frameTimeCounter;
uniform vec3 cameraPosition;

#ifdef IS_IRIS
uniform bool hasSkylight;
#endif

float getDimensionSkyFactor() {
#ifdef IS_IRIS
    return hasSkylight ? 1.0 : 0.0;
#else
    return 1.0;
#endif
}

#endif
