#ifndef SKY_GLSL
#define SKY_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "lighting.glsl"

// Procedural sky gradient blended by view-direction height and the
// current sun/moon light color - deliberately painterly/golden-hour-
// forward rather than a strict Rayleigh scattering model, per the
// stated visual goal.
vec3 skyGradient(vec3 viewDir, vec3 lightDir, vec3 lightColor, float dayFactor) {
    vec3 zenithColor  = mix(vec3(0.02, 0.03, 0.08), vec3(0.25, 0.45, 0.75), dayFactor);
    vec3 horizonColor = mix(vec3(0.05, 0.05, 0.10), lightColor * 0.9, 0.55 + 0.3 * dayFactor);

    float heightFactor = clamp(viewDir.y * 0.9 + 0.15, 0.0, 1.0);
    vec3 sky = mix(horizonColor, zenithColor, pow(heightFactor, 0.55));

    // Extra warm bloom around the horizon band during golden hour.
    float horizonBand = 1.0 - clamp(abs(viewDir.y) * 3.0, 0.0, 1.0);
    sky += lightColor * horizonBand * (1.0 - dayFactor * 0.4) * 0.15 * GOLDEN_HOUR_STRENGTH;

    return sky;
}

// Soft glow disc around the sun/moon direction - additive, no actual
// textured sun quad needed since we're painting the whole sky
// procedurally in the composite pass.
vec3 sunMoonGlow(vec3 viewDir, vec3 lightDir, vec3 lightColor) {
    float d = max(dot(viewDir, lightDir), 0.0);
    float core = smoothstep(1.0 - SUN_GLOW_SIZE * 0.15, 1.0, d);
    float glow = pow(d, 60.0) * 0.5 + pow(d, 8.0) * 0.15;
    return lightColor * (core * 2.0 + glow);
}

// Two-layer scrolling fbm cloud field, projected onto a flat plane at
// CLOUD_HEIGHT. "Volumetric-style" rather than truly volumetric: this
// is a 2D plane with layered noise and a soft density falloff at its
// edges, which reads as soft drifting clouds without a 3D raymarch -
// the actual "volumetric clouds" feature (light marching through a
// 3D density field) is a substantially heavier effect that isn't a
// good performance trade for a single visual layer like this.
float cloudDensity(vec3 viewDir, vec3 cameraWorldPos, float time) {
    if (viewDir.y <= 0.02) return 0.0;

    float dist = (CLOUD_HEIGHT - cameraWorldPos.y) / viewDir.y;
    vec2 cloudPos = cameraWorldPos.xz + viewDir.xz * dist;
    cloudPos *= 0.0025;
    cloudPos += time * CLOUD_SPEED * 0.01;

    float base = fbm(cloudPos, 4);
    float detail = fbm(cloudPos * 3.3 + 7.0, 2) * 0.25;
    float density = smoothstep(1.0 - CLOUD_COVERAGE, 1.0, base + detail);

    // Fade clouds out near the horizon so the flat plane's edge isn't
    // an obvious hard line.
    density *= smoothstep(0.02, 0.2, viewDir.y);
    return clamp(density, 0.0, 1.0);
}

#endif // SKY_GLSL
