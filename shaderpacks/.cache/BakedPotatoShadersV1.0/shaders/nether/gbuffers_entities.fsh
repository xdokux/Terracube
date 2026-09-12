#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"
#include "/lib/nether_lighting.glsl"
#include "/lib/nether_fog.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;
uniform vec4 entityColor;

varying vec2 vTexCoord;
varying vec2 vLightmapCoord;
varying vec4 vColor;
varying vec3 vNormalWorld;
varying vec3 vPlayerPosition;
varying vec4 vLightingState0;
varying vec4 vLightingState1;

void main() {
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < alphaTestRef) discard;
    texel.rgb = mix(texel.rgb, entityColor.rgb, entityColor.a);
    vec3 albedo = srgbToLinearFast(texel.rgb);
    vec3 color = evaluateLighting(albedo, vNormalWorld, vPlayerPosition, vLightmapCoord, 1.0,
                                  vLightingState0, vLightingState1);
    color = applyAtmosphericFog(color, vPlayerPosition);
    gl_FragData[0] = vec4(color, texel.a);
}
