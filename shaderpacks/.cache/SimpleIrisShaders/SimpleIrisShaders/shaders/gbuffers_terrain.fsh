/*
    gbuffers_terrain.fsh
    ---------------------------------------------------------------
    Pipeline stage: GBUFFERS_TERRAIN (opaque block geometry)
    Reads: block texture, lightmap, shadow map, sun/moon direction
    Writes: final lit color for opaque terrain, straight to the
            frame's color buffer (forward shading, no G-buffer)
    ---------------------------------------------------------------
*/
#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"
#include "lib/shadows.glsl"

uniform sampler2D texture;   // block atlas, bound by vanilla/Iris
uniform sampler2D lightmap;  // vanilla sky/block light lightmap
uniform float far;

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;

void main() {
    vec4 albedo = texture2D(texture, texCoord) * vertexColor;
    if (albedo.a < 0.1) discard; // cutout foliage/leaves etc.

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);
    vec3 lightColor = getSunMoonColor(dayFactor);

    // Vanilla lightmap gives us sky light (sun/moon ambient + time of
    // day baked in) and block light (torches etc.) as a single 2D
    // texture lookup - essentially free, and it's why we don't need
    // a separate colored point-light system for torches in this
    // simplified pack.
    vec3 lightmapColor = texture2D(lightmap, lightMapCoord).rgb;

    float diffuse = halfLambert(normal, lightDir);
    float shadow = sampleShadow(viewPos);

    // Sky-light component of the lightmap already tells us whether
    // this fragment can see the sky at all (caves stay dark even if
    // the shadow map alone would say "lit"), so we gate the direct
    // sun/moon contribution by it in addition to the shadow term.
    float skyVisibility = lightMapCoord.y;
    float directLight = diffuse * shadow * skyVisibility;

    vec3 litColor = albedo.rgb * lightmapColor * (0.55 + directLight * lightColor * 1.4);

    // Fog: exponential, starting a bit before vanilla's own fog
    // distance so the transition is less abrupt at low render
    // distances (which the igpu profile encourages).
    float dist = length(viewPos);
    float fogAmount = expFog(dist, far * FOG_START_MULT, far);
    vec3 fogColorAdjusted = mix(gl_Fog.color.rgb, lightColor * 0.6, 0.3);
    litColor = mix(litColor, fogColorAdjusted, fogAmount);

    gl_FragColor = vec4(litColor, albedo.a);
}
