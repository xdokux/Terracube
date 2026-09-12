#version 330 compatibility
/* DRAWBUFFERS:01 */
// gl_FragData[0] -> colortex0 (final toon-shaded color)
// gl_FragData[1] -> colortex1 (view-space normal, for composite's
// edge-detection outline pass - this is the "extra G-buffer" this
// pack needs that the other packs in this series didn't).

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"
#include "lib/shadows.glsl"

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform float far;

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;

void main() {
    vec4 albedo = texture2D(texture, texCoord) * vertexColor;
    if (albedo.a < 0.1) discard;

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);
    vec3 lightColor = getSunMoonColor(dayFactor);
    vec3 lightmapColor = texture2D(lightmap, lightMapCoord).rgb;

    float banded = bandedDiffuse(normal, lightDir);
    float shadow = sampleShadow(viewPos);
    float skyVisibility = lightMapCoord.y;
    float directLight = banded * shadow * skyVisibility;

    float ambient = 0.35; // deliberately high flat ambient - toon
                           // shading wants a bright, readable base
                           // rather than deep realistic shadow falloff
    vec3 litColor = albedo.rgb * lightmapColor * (ambient + directLight * lightColor * 0.9);
    litColor = adjustSaturation(litColor, SATURATION);
    litColor = posterize(litColor, float(POSTERIZE_LEVELS));

    float dist = length(viewPos);
    float fogAmount = clamp((dist - far * 0.75) / (far * 0.25), 0.0, 1.0);
    litColor = mix(litColor, gl_Fog.color.rgb, fogAmount);

    gl_FragData[0] = vec4(litColor, albedo.a);
    gl_FragData[1] = vec4(normal * 0.5 + 0.5, 1.0);
}
