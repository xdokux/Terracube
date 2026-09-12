#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"
#include "/lib/lighting.glsl"
#include "/lib/fog.glsl"
#include "/lib/overworld_water.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

varying vec2 vTexCoord;
varying vec2 vLightmapCoord;
varying vec4 vColor;
varying vec3 vNormalWorld;
varying vec3 vPlayerPosition;
varying vec3 vWorldPosition;
varying float vIsWater;

void main() {
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < alphaTestRef) discard;

    vec4 temporalState;
    vec4 sunState;
    vec3 moonDirection;
    getAtmosphereState(temporalState, sunState, moonDirection);

    vec4 outputColor;
    vec3 resolvedWaterNormal = vec3(0.0, 1.0, 0.0);
    if (vIsWater > 0.5) {
        outputColor = shadeOverworldWater(vPlayerPosition, vWorldPosition, vNormalWorld, texel,
                                          temporalState, sunState, moonDirection,
                                          resolvedWaterNormal);
        outputColor.rgb = applyAtmosphericFog(outputColor.rgb, vPlayerPosition,
                                              temporalState, sunState, moonDirection);
    } else {
        vec3 color = evaluateLighting(srgbToLinearFast(texel.rgb), vNormalWorld, vPlayerPosition,
                                      vLightmapCoord, 1.0, temporalState, sunState, moonDirection);
        color = applyAtmosphericFog(color, vPlayerPosition,
                                    temporalState, sunState, moonDirection);
        outputColor = vec4(color, texel.a);
    }

    gl_FragData[0] = outputColor;

    // Compact water-only metadata for the removable reflection pass:
    // RG = wave-normal XZ, B = normalized camera distance, A = overwrite alpha.
    float topWaterSurface = vIsWater * step(0.45, vNormalWorld.y);
    vec4 reflectionData = vec4(0.0, 0.0, 0.0, 1.0);
    if (topWaterSurface > 0.5) {
        // Amplification preserves the very small calm-wave slopes in RGBA8.
        vec2 encodedNormal = saturate(resolvedWaterNormal.xz * 6.0 + 0.5);
        float encodedDistance = max(saturate(length(vPlayerPosition) / far), 1.0 / 255.0);
        reflectionData = vec4(encodedNormal, encodedDistance, 1.0);
    }
    gl_FragData[1] = reflectionData;
}

/* RENDERTARGETS: 0,3 */
