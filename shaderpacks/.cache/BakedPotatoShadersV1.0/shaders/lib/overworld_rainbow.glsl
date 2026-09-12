#ifndef CINDERLIGHT_OVERWORLD_RAINBOW_GLSL
#define CINDERLIGHT_OVERWORLD_RAINBOW_GLSL

#include "/lib/math.glsl"

vec3 getRainbowSpectrum(float t) {
    t = saturate(t);

    vec3 red = vec3(0.640, 0.120, 0.085);
    vec3 orange = vec3(0.760, 0.285, 0.075);
    vec3 yellow = vec3(0.780, 0.610, 0.145);
    vec3 green = vec3(0.150, 0.570, 0.245);
    vec3 cyan = vec3(0.105, 0.405, 0.560);
    vec3 blue = vec3(0.115, 0.205, 0.560);
    vec3 violet = vec3(0.315, 0.120, 0.500);

    if (t < 0.1666667) return mix(red, orange, smoothstep(0.0, 0.1666667, t));
    if (t < 0.3333333) return mix(orange, yellow, smoothstep(0.1666667, 0.3333333, t));
    if (t < 0.5000000) return mix(yellow, green, smoothstep(0.3333333, 0.5000000, t));
    if (t < 0.6666667) return mix(green, cyan, smoothstep(0.5000000, 0.6666667, t));
    if (t < 0.8333333) return mix(cyan, blue, smoothstep(0.6666667, 0.8333333, t));
    return mix(blue, violet, smoothstep(0.8333333, 1.0, t));
}

float getPostRainRainbowTimer(float rain, float timerState) {
    // timerState is an independent CPU-side custom uniform. It is reset to 1
    // while rain is active, then decays with a 5-second half-life only after
    // rainStrength reaches exactly zero. These thresholds map that decay to:
    // 0-3 s fade-in, 3-17 s full visibility, 17-20 s fade-out, then hard zero.
    const float timerAt3Seconds = 0.659753955;
    const float timerAt17Seconds = 0.094732286;
    const float timerAt20Seconds = 0.062500000;

    float dryGate = 1.0 - sign(rain);
    float activeTimer = step(timerAt20Seconds, timerState);
    float fadeIn = 1.0 - smoothstep(timerAt3Seconds, 1.0, timerState);
    float fadeOut = smoothstep(timerAt20Seconds, timerAt17Seconds, timerState);
    return dryGate * activeTimer * fadeIn * fadeOut;
}

vec3 getPostRainRainbow(vec3 direction, vec3 sunDirection,
                        float rain, float timerState) {
    float timer = getPostRainRainbowTimer(rain, timerState);
    float daylight = smoothstep(-0.035, 0.115, sunDirection.y);
    if (timer <= 0.0 || daylight <= 0.0 || direction.y <= -0.025) return vec3(0.0);

    vec3 sun = safeNormalize(sunDirection);

    // A physical rainbow is centred on the antisolar point. When the sun is
    // high, the true cone falls below the visible horizon; clamping only the
    // centre elevation preserves the opposite-sun azimuth while keeping the
    // post-rain arc visible and stable in Minecraft's sky dome.
    vec2 antiAzimuth = -sun.xz;
    float azimuthLength = length(antiAzimuth);
    if (azimuthLength < 0.0001) antiAzimuth = vec2(1.0, 0.0);
    else antiAzimuth /= azimuthLength;

    float centreDrop = min(max(sun.y, 0.0), 0.42);
    vec3 rainbowCentre = safeNormalize(vec3(antiAzimuth.x, -centreDrop, antiAzimuth.y));
    float angularDot = dot(direction, rainbowCentre);

    // Primary rainbow radius: approximately 42 degrees from the antisolar point.
    const float rainbowCosine = 0.743145;
    const float halfWidth = 0.044;
    float radialOffset = angularDot - rainbowCosine;
    if (abs(radialOffset) >= halfWidth) return vec3(0.0);

    float bandPosition = saturate((radialOffset + halfWidth) / (2.0 * halfWidth));
    float featheredBand = smoothstep(0.0, 0.18, bandPosition) *
                          (1.0 - smoothstep(0.82, 1.0, bandPosition));
    float atmosphericFade = smoothstep(-0.025, 0.065, direction.y) *
                            (1.0 - smoothstep(0.84, 0.98, direction.y));

    vec3 spectrum = getRainbowSpectrum(bandPosition);
    float softCore = 0.78 + 0.22 * smoothstep(0.20, 0.80, bandPosition) *
                                   (1.0 - smoothstep(0.62, 0.92, bandPosition));
    float opacity = timer * daylight * featheredBand * atmosphericFade * softCore * 0.255;
    return spectrum * opacity;
}

#endif
