#version 330 compatibility
/* DRAWBUFFERS:01 */

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"
#include "lib/shadows.glsl"

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform vec4 entityColor;
uniform float far;

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;

void main() {
    vec4 albedo = texture2D(texture, texCoord) * vertexColor;
    if (albedo.a < 0.1) discard;
    albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);
    vec3 lightColor = getSunMoonColor(dayFactor);
    vec3 lightmapColor = texture2D(lightmap, lightMapCoord).rgb;

    float banded = bandedDiffuse(normal, lightDir);
    float shadow = sampleShadow(viewPos);
    float skyVisibility = lightMapCoord.y;
    float directLight = banded * shadow * skyVisibility;

    vec3 viewDir = normalize(-viewPos);
    float rim = rimLight(normal, viewDir) * skyVisibility;

    float ambient = 0.35;
    vec3 litColor = albedo.rgb * lightmapColor * (ambient + directLight * lightColor * 0.9);
    litColor += lightColor * rim;
    litColor = adjustSaturation(litColor, SATURATION);
    litColor = posterize(litColor, float(POSTERIZE_LEVELS));

    float dist = length(viewPos);
    float fogAmount = clamp((dist - far * 0.75) / (far * 0.25), 0.0, 1.0);
    litColor = mix(litColor, gl_Fog.color.rgb, fogAmount);

    gl_FragData[0] = vec4(litColor, albedo.a);
    gl_FragData[1] = vec4(normal * 0.5 + 0.5, 1.0);
}
