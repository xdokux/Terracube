#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"
#include "lib/shadows.glsl"
#include "lib/water.glsl"

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform float far;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;
varying float blockId;

void main() {
    vec4 albedo = texture2D(texture, texCoord) * vertexColor;
    if (albedo.a < 0.1) discard;

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);
    vec3 lightColor = getSunMoonColor(dayFactor);

    vec3 lightmapColor = texture2D(lightmap, lightMapCoord).rgb;
    lightmapColor = tintBlockLight(lightmapColor, lightMapCoord.x, blockId);

    float diffuse = halfLambert(normal, lightDir);
    float shadow = sampleShadow(viewPos);
    float skyVisibility = lightMapCoord.y;
    float directLight = diffuse * shadow * skyVisibility;

    // Puddle patches on rain-facing terrain: darken albedo slightly
    // and add a specular-ish highlight so wet ground actually reads
    // as wet rather than just "a bit darker".
    vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
    vec2 worldXZ = worldPos.xz + cameraPosition.xz;

    float puddle = puddleMask(worldXZ, normal, rainStrength);
    vec3 wetAlbedo = mix(albedo.rgb, albedo.rgb * 0.7, puddle);
    float puddleSpec = pow(diffuse, 24.0) * puddle * shadow * 0.8;

    // Ambient floor: guarantees caves and unlit night terrain never
    // go pure black, regardless of shadow/sky-light state. This is
    // the direct fix for the "pitch-black underground" failure mode
    // called out in the brief.
    float ambient = max(MIN_AMBIENT, (1.0 - skyVisibility) * 0.03);

    vec3 litColor = wetAlbedo * lightmapColor * (ambient + directLight * lightColor * 1.4);
    litColor += lightColor * puddleSpec;

    // Height-based fog: thickens close to a reference height (roughly
    // sea level) rather than uniformly with distance, so valleys/
    // caves read hazier than mountaintops.
#if HEIGHT_FOG == 1
    float heightDiff = max(0.0, HEIGHT_FOG_FALLOFF_Y - worldPos.y - cameraPosition.y);
    float heightFogAmount = 1.0 - exp(-heightDiff * HEIGHT_FOG_DENSITY * 0.01);
    float dist = length(viewPos);
    float distFogAmount = expFog(dist, far * 0.7, far);
    float fogAmount = clamp(max(heightFogAmount * clamp(dist / far, 0.0, 1.0), distFogAmount), 0.0, 1.0);
#else
    float dist = length(viewPos);
    float fogAmount = expFog(dist, far * 0.7, far);
#endif

    vec3 fogColorAdjusted = mix(gl_Fog.color.rgb, lightColor * 0.6, 0.35);
    litColor = mix(litColor, fogColorAdjusted, fogAmount);

    gl_FragColor = vec4(litColor, albedo.a);
}
