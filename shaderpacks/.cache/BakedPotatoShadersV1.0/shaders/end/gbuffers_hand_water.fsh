#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"
#include "/lib/held_emission.glsl"
#include "/lib/end_lighting.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;
uniform int currentRenderedItemId;

varying vec2 vTexCoord;
varying vec2 vLightmapCoord;
varying vec4 vColor;
varying vec3 vNormalWorld;
varying vec4 vLightingState0;
varying vec4 vLightingState1;

void main() {
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < alphaTestRef) discard;
    vec3 albedo = srgbToLinearFast(texel.rgb);
    vec3 color = evaluateLighting(albedo, vNormalWorld, vec3(0.0),
                                  vLightmapCoord, 0.0, vLightingState0, vLightingState1);
    color += getHeldItemSelfEmission(albedo, currentRenderedItemId);
    gl_FragData[0] = vec4(color, texel.a);
}
