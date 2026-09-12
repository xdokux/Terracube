/*
    gbuffers_entities.fsh
    ---------------------------------------------------------------
    Pipeline stage: GBUFFERS_ENTITIES (mobs, players, item frames...)
    Identical lighting model to terrain; the only entity-specific bit
    is blending in entityColor (the red damage-flash / spectral tint
    vanilla applies to entities).
    ---------------------------------------------------------------
*/
#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"
#include "lib/shadows.glsl"

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform vec4 entityColor; // vanilla damage-flash / potion tint overlay
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

    float diffuse = halfLambert(normal, lightDir);
    float shadow = sampleShadow(viewPos);
    float skyVisibility = lightMapCoord.y;
    float directLight = diffuse * shadow * skyVisibility;

    vec3 litColor = albedo.rgb * lightmapColor * (0.55 + directLight * lightColor * 1.4);

    float dist = length(viewPos);
    float fogAmount = expFog(dist, far * FOG_START_MULT, far);
    vec3 fogColorAdjusted = mix(gl_Fog.color.rgb, lightColor * 0.6, 0.3);
    litColor = mix(litColor, fogColorAdjusted, fogAmount);

    gl_FragColor = vec4(litColor, albedo.a);
}
