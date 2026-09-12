#ifndef LIGHTING_GLSL
#define LIGHTING_GLSL

#include "settings.glsl"

uniform vec3 shadowLightPosition;

vec3 getShadowLightDirection() {
    return normalize(shadowLightPosition);
}

// Deliberately just N.L, no view-vector term anywhere in this pack.
// Any dot(normal, viewDir) - fresnel, rim light, cheap specular - by
// definition changes as you rotate the camera even though nothing in
// the world moved, which is exactly the "tone shifts as I look
// around" bug you're asking to avoid. So it's just not here.
float diffuse(vec3 normal, vec3 lightDir) {
    return max(dot(normal, lightDir), 0.0);
}

// day/night as a plain function of sun elevation - camera-independent,
// stable no matter which way you're facing.
float getDayFactor(vec3 lightDir) {
    return clamp(lightDir.y * 1.3 + 0.15, 0.0, 1.0);
}

vec3 getSunMoonColor(float dayFactor) {
    vec3 day   = vec3(1.0, 1.0, 1.0);
    vec3 night = vec3(0.45, 0.5, 0.65);
    return mix(night, day, smoothstep(0.0, 0.4, dayFactor));
}

#endif // LIGHTING_GLSL
