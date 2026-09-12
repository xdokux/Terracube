#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"
#include "/lib/end_lighting.glsl"
#include "/lib/end_fog.glsl"
#include "/lib/end_materials.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

varying vec2 vTexCoord;
varying vec2 vLightmapCoord;
varying vec4 vColor;
varying vec3 vNormalWorld;
varying vec3 vPlayerPosition;
varying vec4 vLightingState0;
varying vec4 vLightingState1;
varying float vMaterialId;

void main() {
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < alphaTestRef) discard;
    vec3 albedo = srgbToLinearFast(texel.rgb);
    vec3 color = evaluateLighting(albedo, vNormalWorld, vPlayerPosition, vLightmapCoord, 0.0,
                                  vLightingState0, vLightingState1);
    color = applyEndMaterialEmission(color, albedo, vMaterialId);
    color = applyAtmosphericFog(color, vPlayerPosition);
    gl_FragData[0] = vec4(color, texel.a);
}
