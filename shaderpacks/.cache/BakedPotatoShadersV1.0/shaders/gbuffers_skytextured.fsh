#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"
#include "/lib/sky.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

varying vec2 vTexCoord;
varying vec4 vColor;
varying vec3 vWorldDirection;

void main() {
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    float bodyCoverage = step(alphaTestRef, texel.a);
    float bodyAlpha = texel.a * bodyCoverage;
    if (bodyAlpha <= 0.0) discard;

    vec3 direction = normalize(vWorldDirection);
    float timeOfDay = getTimeOfDayNormalized();
    vec3 sunDirection = getSunDirection();
    vec3 moonDirection = getMoonDirection();
    float sunrise = getSunrisePhaseAmount(timeOfDay);
    float sunset = getSunsetPhaseAmount(timeOfDay);
    float sunAlignment = dot(direction, sunDirection);
    float moonAlignment = dot(direction, moonDirection);
    float isSun = step(moonAlignment, sunAlignment);
    float sunElevation = smoothstep(-0.08, 0.32, sunDirection.y);
    float moonElevation = smoothstep(-0.12, 0.28, moonDirection.y);
    vec3 sunTint = getSunDiscColor(timeOfDay, sunrise, sunset, sunDirection);
    vec3 moonTint = mix(vec3(0.42, 0.52, 0.72), vec3(0.64, 0.73, 0.90), moonElevation);
    vec3 tint = mix(moonTint, sunTint, isSun);

    float lowSun = max(sunrise, sunset);
    float sunIntensity = mix(1.82, 2.10, sunElevation) + lowSun * 0.08;
    float intensity = mix(0.86, sunIntensity, isSun);
    vec3 bodyColor = srgbToLinearFast(texel.rgb) * tint * intensity;

    gl_FragData[0] = vec4(bodyColor, bodyAlpha);
}
