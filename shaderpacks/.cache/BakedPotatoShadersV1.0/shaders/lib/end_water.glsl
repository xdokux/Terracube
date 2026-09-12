#ifndef CINDERLIGHT_END_WATER_GLSL
#define CINDERLIGHT_END_WATER_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/water_waves.glsl"
#include "/lib/end_common.glsl"

vec4 shadeEndWater(vec3 playerPosition, vec3 worldPosition, vec3 geometricNormal,
                   vec4 textureColor) {
    vec3 viewDirection = safeNormalize(-playerPosition);
    vec3 normal = geometricNormal.y > 0.45 ? getWaterNormal(worldPosition.xz) :
                                             safeNormalize(geometricNormal);
    float viewFacing = saturate(dot(normal, viewDirection));
    float fresnel = 0.060 + 0.73 * pow5(1.0 - viewFacing);
    vec3 reflectedDirection = reflect(-viewDirection, normal);
    vec3 reflection = getEndReflectionSky(reflectedDirection);
    vec3 waterBody = vec3(0.006, 0.012, 0.030) * mix(0.74, 1.0, textureColor.b);

#if WATER_QUALITY == 0
    fresnel *= 0.72;
#elif WATER_QUALITY == 2
    fresnel *= 1.08;
#endif

    vec3 color = mix(waterBody, reflection, saturate(fresnel));
    float alpha = mix(0.31, 0.60, saturate(fresnel + (1.0 - viewFacing) * 0.25));
    alpha *= mix(0.82, 1.0, textureColor.a);
    return vec4(color, saturate(alpha));
}

#endif
