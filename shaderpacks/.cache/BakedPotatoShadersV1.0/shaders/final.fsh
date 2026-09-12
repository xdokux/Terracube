#version 120

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/tonemap.glsl"
#include "/lib/weather.glsl"
#include "/lib/overworld_biome_fog.glsl"

uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform ivec2 eyeBrightnessSmooth;
uniform int isEyeInWater;
uniform float rainStrength;

varying vec2 vTexCoord;

void main() {
    vec3 color = texture2D(colortex1, vTexCoord).rgb;

    float eyeSky = saturate(float(eyeBrightnessSmooth.y) / 240.0);
    float outdoorSky = smoothstep(0.18, 0.58, eyeSky);
    float cave = 1.0 - smoothstep(0.05, 0.40, eyeSky);
    color += vec3(0.0065, 0.0070, 0.0075) * cave * CAVE_BRIGHTNESS;

    if (isEyeInWater == 1) {
        color = mix(color, color * vec3(0.62, 0.88, 0.92) + vec3(0.004, 0.020, 0.024), 0.10);
    } else {
        float rain = saturate(rainStrength);
        float wetAtmosphere = rain * outdoorSky;
        float sceneLuminance = luminance(color);
        vec3 softenedColor = mix(color, vec3(sceneLuminance), 0.035);
        softenedColor = softenedColor * 0.985 + vec3(0.0035);
        color = mix(color, softenedColor, wetAtmosphere);
    }

    float lightningFlash = getWeatherLightningFlash();
    color = applyWeatherLightning(color, lightningFlash, 0.68, 0.10, 0.018);

    color = finishColor(color);

    vec2 centered = vTexCoord * 2.0 - 1.0;
    float vignette = 1.0 - dot(centered, centered) * 0.035;
    float vignetteFactor = clamp(vignette, 0.90, 1.0);
    color *= vignetteFactor;

    // Preserve the existing vignette darkness exactly. Only its corner chroma
    // inherits 7.5% of the active smoothed biome-fog palette, with matched
    // luminance so the vignette does not become stronger or brighter.
    if (isEyeInWater == 0 && outdoorSky > 0.0) {
        float vignetteEdge = smoothstep(0.0, 0.07, 1.0 - vignetteFactor);
        vec3 vignetteFogColor = matchBiomeFogLuminance(getOverworldBiomeFogTint(), luminance(color));
        color = mix(color, vignetteFogColor, vignetteEdge * outdoorSky * 0.075);
    }

    vec4 lineOverlay = texture2D(colortex2, vTexCoord);
    if (lineOverlay.a > 0.0) {
        color = mix(color, lineOverlay.rgb, lineOverlay.a);
    }

    gl_FragColor = vec4(color, 1.0);
}
