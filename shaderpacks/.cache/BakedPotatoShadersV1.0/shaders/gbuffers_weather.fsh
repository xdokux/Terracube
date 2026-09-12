#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"
#include "/lib/fog.glsl"
#include "/lib/weather.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

varying vec2 vTexCoord;
varying vec4 vColor;
varying vec3 vPlayerPosition;

void main() {
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    float rain = saturate(rainStrength);
    float weatherAlphaTest = mix(alphaTestRef, alphaTestRef * 0.55, rain);
    if (texel.a < weatherAlphaTest) discard;

    float coverage = smoothstep(weatherAlphaTest, weatherAlphaTest + 0.32, texel.a);
    vec3 rainTint = mix(vec3(0.78, 0.84, 0.88), vec3(0.82, 0.86, 0.88), rain);
    vec3 color = srgbToLinearFast(texel.rgb) * rainTint;

    float lightningFlash = getWeatherLightningFlash();
    color = applyWeatherLightning(color, lightningFlash, 0.72, 0.13, 0.018);
    color = applyAtmosphericFog(color, vPlayerPosition);

    float alpha = (texel.a * 0.68 + coverage * 0.22) * mix(0.91, 0.98, rain);
    gl_FragData[0] = vec4(color, min(alpha, 0.88));
}
