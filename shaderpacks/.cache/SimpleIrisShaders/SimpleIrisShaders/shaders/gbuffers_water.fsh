/*
    gbuffers_water.fsh
    ---------------------------------------------------------------
    Pipeline stage: GBUFFERS_WATER (water + translucent geometry)
    Same sun/shadow lighting model as terrain, plus a slightly
    stronger specular-ish highlight so waves read visually, and an
    underwater fog term applied when the camera itself is submerged.

    No screen-space reflections, no reflection cubemap, no fresnel-
    driven mirror term - explicitly out of scope per your request.
    ---------------------------------------------------------------
*/
#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"
#include "lib/shadows.glsl"

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform float far;
uniform int isEyeInWater; // vanilla/Iris uniform: 1 if camera is underwater

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;
varying float isLikelyWater;

void main() {
    vec4 albedo = texture2D(texture, texCoord) * vertexColor;
    if (albedo.a < 0.05) discard;

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);
    vec3 lightColor = getSunMoonColor(dayFactor);
    vec3 lightmapColor = texture2D(lightmap, lightMapCoord).rgb;

    float diffuse = halfLambert(normal, lightDir);
    float shadow = sampleShadow(viewPos);
    float skyVisibility = lightMapCoord.y;
    float directLight = diffuse * shadow * skyVisibility;

    // A cheap, non-physical "shimmer" highlight on water only, using
    // the same half-Lambert term raised to a power - not a real
    // specular BRDF, just enough to make the waves visibly catch
    // light without adding a view-vector-dependent reflection pass.
    float shimmer = pow(diffuse, 12.0) * isLikelyWater * shadow * 0.6;

    vec3 litColor = albedo.rgb * lightmapColor * (0.55 + directLight * lightColor * 1.4);
    litColor += lightColor * shimmer;

    float dist = length(viewPos);

    if (isEyeInWater == 1) {
        float fogAmount = underwaterFog(dist, UNDERWATER_FOG_DENSITY);
        vec3 underwaterTint = vec3(0.05, 0.20, 0.28) * (0.5 + dayFactor * 0.5);
        litColor = mix(litColor, underwaterTint, fogAmount);
    } else {
        float fogAmount = expFog(dist, far * FOG_START_MULT, far);
        vec3 fogColorAdjusted = mix(gl_Fog.color.rgb, lightColor * 0.6, 0.3);
        litColor = mix(litColor, fogColorAdjusted, fogAmount);
    }

    gl_FragColor = vec4(litColor, albedo.a);
}
