#ifndef CINDERLIGHT_OVERWORLD_WATER_GLSL
#define CINDERLIGHT_OVERWORLD_WATER_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/sky.glsl"
#include "/lib/overworld_water_waves.glsl"

// Base water shading is intentionally kept equivalent to the previous water
// implementation. The only added output is the already-resolved surface normal
// used by the removable screen-space reflection pass.
vec4 shadeOverworldWater(vec3 playerPosition, vec3 worldPosition, vec3 geometricNormal,
                         vec4 textureColor, vec4 temporalState, vec4 sunState,
                         vec3 moonDirection, out vec3 surfaceNormal) {
    vec3 viewDirection = safeNormalize(-playerPosition);
    float timeOfDay = temporalState.x;
    float day = temporalState.y;
    float twilight = temporalState.z;
    float sunrise = temporalState.w;
    vec3 sunDirection = sunState.xyz;
    float sunset = sunState.w;

    surfaceNormal = geometricNormal.y > 0.45
                  ? getOverworldWaterNormal(worldPosition.xz)
                  : safeNormalize(geometricNormal);
    float viewFacing = saturate(dot(surfaceNormal, viewDirection));
    float fresnel = 0.060 + 0.73 * pow5(1.0 - viewFacing);

    vec3 reflectedDirection = reflect(-viewDirection, surfaceNormal);
    vec3 skyReflectionDirection = safeNormalize(reflectedDirection);
    vec3 reflection = getSkyColorResolved(skyReflectionDirection, timeOfDay, day, twilight,
                                          sunDirection, moonDirection, sunrise, sunset);
    reflection = mix(reflection, getTwilightAtmosphereColor(reflectedDirection, sunDirection),
                     getTwilightAtmosphereAmount(reflectedDirection, twilight) * 0.82);
    reflection *= mix(0.88, 1.10, day);
    float sunGlint = pow96(max(dot(reflectedDirection, sunDirection), 0.0)) * day;
    reflection += vec3(1.00, 0.78, 0.48) * sunGlint * 0.27;
    vec3 waterBody = mix(vec3(0.009, 0.088, 0.105), vec3(0.014, 0.136, 0.153), day);
    waterBody *= mix(0.72, 1.0, textureColor.g);

#if WATER_QUALITY == 0
    fresnel *= 0.72;
#elif WATER_QUALITY == 2
    fresnel *= 1.08;
#endif

    vec3 color = mix(waterBody, reflection, saturate(fresnel));
    color += vec3(0.015, 0.035, 0.040) * max(surfaceNormal.y, 0.0) * day;
    float alpha = mix(0.29, 0.58, saturate(fresnel + (1.0 - viewFacing) * 0.25));
    alpha *= mix(0.82, 1.0, textureColor.a);
    return vec4(color, saturate(alpha));
}

#endif
