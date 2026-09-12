#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"
#include "/lib/end_lighting.glsl"
#include "/lib/end_fog.glsl"
#include "/lib/end_water.glsl"
#include "/lib/end_materials.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

varying vec2 vTexCoord;
varying vec2 vLightmapCoord;
varying vec4 vColor;
varying vec3 vNormalWorld;
varying vec3 vPlayerPosition;
varying vec3 vWorldPosition;
varying float vIsWater;
varying float vMaterialId;

void main() {
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < alphaTestRef) discard;

    vec4 outputColor;
    if (vIsWater > 0.5) {
        outputColor = shadeEndWater(vPlayerPosition, vWorldPosition, vNormalWorld, texel);
        outputColor.rgb = applyAtmosphericFog(outputColor.rgb, vPlayerPosition);
    } else {
        vec3 albedo = srgbToLinearFast(texel.rgb);
        vec3 color = evaluateLighting(albedo, vNormalWorld, vPlayerPosition,
                                      vLightmapCoord, 0.0);
        color = applyEndMaterialEmission(color, albedo, vMaterialId);
        color = applyAtmosphericFog(color, vPlayerPosition);
        outputColor = vec4(color, texel.a);
    }

    gl_FragData[0] = outputColor;
}
