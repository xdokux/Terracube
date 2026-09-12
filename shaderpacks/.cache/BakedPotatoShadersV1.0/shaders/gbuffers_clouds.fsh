#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"
#include "/lib/time.glsl"
#include "/lib/sky.glsl"
#include "/lib/weather.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

varying vec2 vTexCoord;
varying vec4 vColor;
varying vec3 vPlayerPosition;
varying vec3 vNormalWorld;

void main() {
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    float rain = saturate(rainStrength);
    float weatherAlphaTest = mix(alphaTestRef, alphaTestRef * 0.72, rain);
    if (texel.a < weatherAlphaTest) discard;
    vec4 temporalState;
    vec4 sunState;
    vec3 moonDirection;
    getAtmosphereState(temporalState, sunState, moonDirection);
    vec3 sunDirection = sunState.xyz;
    float day = temporalState.y;
    float twilight = temporalState.z;
    vec3 normalWorld = safeNormalize(vNormalWorld);
    float topFacing = normalWorld.y * 0.5 + 0.5;
    float sideAmount = 1.0 - abs(normalWorld.y);
    float faceLight = mix(0.72, 1.08, topFacing) * mix(1.0, 0.92, sideAmount);
    faceLight += max(dot(normalWorld, sunDirection), 0.0) * day * 0.10;
    float rainUnderside = mix(0.76, 1.0, topFacing);
    faceLight *= mix(1.0, rainUnderside * 0.96, rain);

    vec3 dayTint = mix(vec3(0.18, 0.23, 0.34), vec3(0.82, 0.84, 0.82), day);
    float sunward = getTwilightHorizonSunward(vPlayerPosition, sunDirection);
    vec3 twilightTint = getTwilightHorizonColor(sunward) * 0.80;
    dayTint = mix(dayTint, twilightTint, twilight * 0.16);
    dayTint = mix(dayTint, vec3(0.31, 0.33, 0.34), rain * 0.82);

    vec3 color = srgbToLinearFast(texel.rgb) * dayTint * faceLight * 1.02;

    float lightningFlash = getWeatherLightningFlash();
    color = applyWeatherLightning(color, lightningFlash, 0.78, 0.15, 0.026);

    float softAlpha = texel.a * smoothstep(alphaTestRef, alphaTestRef + 0.16, texel.a);
    float rainSoftAlpha = texel.a * smoothstep(weatherAlphaTest, weatherAlphaTest + 0.22, texel.a);
    softAlpha = mix(softAlpha, rainSoftAlpha, rain * 0.76);
    gl_FragData[0] = vec4(color, softAlpha * 0.92);
}
