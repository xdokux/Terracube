/*
    lighting.glsl
    ---------------------------------------------------------------
    Directional sun/moon lighting with a smooth day-night blend.
    Everything here is cheap: a handful of dot products and lerps
    per fragment, no texture fetches, so it costs effectively the
    same on a UHD 630 as on a 4090.
    ---------------------------------------------------------------
*/
#ifndef LIGHTING_GLSL
#define LIGHTING_GLSL


// sunPosition / moonPosition / upPosition are standard Iris/OptiFine
// uniforms (view-space direction vectors, already normalized by the
// engine each frame).
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform vec3 shadowLightPosition;
uniform float rainStrength;

// Returns the currently "active" light direction (sun by day, moon by
// night) and how strong it is, so terrain/entities/water all light
// consistently without duplicating the day/night check everywhere.
vec3 getShadowLightDirection() {
    // shadowLightPosition is provided by Iris/OptiFine and already
    // points at whichever of sun/moon is currently casting shadows -
    // using it instead of re-deriving from sunPosition/moonPosition
    // keeps this in sync with the shadow pass automatically.
    return normalize(shadowLightPosition);
}

// Simple half-Lambert diffuse term. Half-Lambert (rather than pure
// N.L) avoids a hard black terminator on blocky terrain normals,
// which looks bad on voxel geometry in particular.
float halfLambert(vec3 normal, vec3 lightDir) {
    float nDotL = dot(normal, lightDir);
    float half_ = nDotL * 0.5 + 0.5;
    return half_ * half_;
}

// Day/night/rain-aware light color and intensity. Kept as simple
// lerps between a small number of authored colors rather than a
// physical sky model - authored colors are cheaper and easier to
// art-direct for a lightweight pack.
vec3 getSunMoonColor(float dayFactor) {
    vec3 dayColor   = vec3(1.05, 1.00, 0.90);
    vec3 sunsetColor = vec3(1.15, 0.65, 0.35);
    vec3 nightColor = vec3(0.28, 0.35, 0.55);

    // dayFactor: 1 = midday, 0 = deep night, with the sunset color
    // taking over in the transition band around the horizon.
    vec3 color = mix(nightColor, dayColor, smoothstep(0.0, 0.35, dayFactor));
    float sunsetBand = 1.0 - abs(dayFactor - 0.2) / 0.2;
    color = mix(color, sunsetColor, clamp(sunsetBand, 0.0, 1.0) * 0.6);

    return color * mix(1.0, 0.55, rainStrength);
}

// 0..1 factor derived from the sun's height above the horizon, used
// to drive getSunMoonColor and fog tinting.
float getDayFactor(vec3 sunDir) {
    return clamp(sunDir.y * 1.3 + 0.15, 0.0, 1.0);
}

#endif // LIGHTING_GLSL
