#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"
#include "lib/shadows.glsl"

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform float far;
uniform int isEyeInWater;

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;
varying float isLikelyWater;
varying vec2 rippleNormalOffset;

void main() {
    vec4 albedo = texture2D(texture, texCoord) * vertexColor;
    if (albedo.a < 0.05) discard;

    // Clear blue tint on water specifically - glass/ice sharing this
    // stage stay closer to their vanilla color.
    if (isLikelyWater > 0.5) {
        albedo.rgb = mix(albedo.rgb, vec3(0.35, 0.62, 0.78), 0.4);
    }

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);
    vec3 lightColor = getSunMoonColor(dayFactor);
    vec3 lightmapColor = tintBlockLight(texture2D(lightmap, lightMapCoord).rgb, lightMapCoord.x, -1.0);

    // Rain ripples perturb the effective normal used for lighting -
    // cheap (no real normal map texture), but reads as broken-up
    // ripple highlights across the surface during rain.
    vec3 rippledNormal = normalize(normal + vec3(rippleNormalOffset.x, 0.0, rippleNormalOffset.y));

    float diffuse = halfLambert(rippledNormal, lightDir);
    float shadow = sampleShadow(viewPos);
    float skyVisibility = lightMapCoord.y;
    float directLight = diffuse * shadow * skyVisibility;
    float ambient = max(MIN_AMBIENT, (1.0 - skyVisibility) * 0.03);

    float shimmer = pow(diffuse, 10.0) * isLikelyWater * shadow * 0.7;

    vec3 litColor = albedo.rgb * lightmapColor * (ambient + directLight * lightColor * 1.4);
    litColor += lightColor * shimmer;

    float dist = length(viewPos);
    if (isEyeInWater == 1) {
        float fogAmount = 1.0 - exp(-dist * 0.10);
        vec3 underwaterTint = vec3(0.04, 0.22, 0.30) * (0.5 + dayFactor * 0.5);
        litColor = mix(litColor, underwaterTint, fogAmount);
    } else {
        float fogAmount = expFog(dist, far * 0.7, far);
        vec3 fogColorAdjusted = mix(gl_Fog.color.rgb, lightColor * 0.6, 0.35);
        litColor = mix(litColor, fogColorAdjusted, fogAmount);
    }

    gl_FragColor = vec4(litColor, albedo.a);
}
