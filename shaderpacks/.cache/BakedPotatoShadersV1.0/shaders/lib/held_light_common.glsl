#ifndef CINDERLIGHT_HELD_LIGHT_COMMON_GLSL
#define CINDERLIGHT_HELD_LIGHT_COMMON_GLSL

vec3 getHeldItemLightColor(int itemId) {
    if (itemId == 11002) return vec3(0.20, 0.72, 1.00);
    if (itemId == 11003) return vec3(0.50, 0.86, 1.00);
    if (itemId == 11004) return vec3(0.52, 1.00, 0.68);
    if (itemId == 11005) return vec3(0.94, 0.64, 1.00);
    if (itemId == 11006) return vec3(0.76, 0.92, 1.00);
    if (itemId == 11007) return vec3(1.00, 0.18, 0.07);
    return vec3(1.00, 0.44, 0.16);
}

#endif
