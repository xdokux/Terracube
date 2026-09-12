#ifndef CINDERLIGHT_OVERWORLD_AURORA_GLSL
#define CINDERLIGHT_OVERWORLD_AURORA_GLSL

#include "/lib/settings.glsl"
#include "/lib/math.glsl"
#include "/lib/procedural.glsl"

#define AURORA_DEBUG_MODE 0 // [0 1] Force the existing aurora every true night.

float getAuroraEventGate(int worldDay, float transitionTime) {
#if AURORA_DEBUG_MODE == 1
    // The visible-sky timeline reaches the true night palette at 0.660 and
    // begins the pre-sunrise blue hour at 0.900. Restrict showcase mode to
    // that exact interval so it cannot leak into sunset, twilight, or dawn.
    return step(0.660, transitionTime) * (1.0 - step(0.900, transitionTime));
#else
    float dayRandom = proceduralHash12(vec2(float(worldDay), float(worldDay) * 0.371 + 83.7));
    return step(0.9925, dayRandom);
#endif
}

// Two smooth noise frequencies are enough to break repetition while remaining
// inexpensive on Apple Silicon. This function is evaluated only on rare,
// clear nights after the early event/weather gates below.
float getAuroraFlowNoise(vec2 position, float animationTime, vec2 velocity) {
    vec2 motion = velocity * animationTime;
    float broad = proceduralValueNoise2D(position + motion);
    float detail = proceduralValueNoise2D(position * 2.13 - motion * 0.61 + vec2(17.4, 31.8));
    return broad * 0.72 + detail * 0.28;
}

// Returns RGB as density-weighted colour and A as curtain density. The layer
// forms a broad, continuous curtain with a bright inner fold, feathered edges,
// faint vertical rays, and a soft surrounding sky glow.
vec4 getAuroraCurtainLayer(vec2 horizontal, float elevation, vec2 axis,
                           float baseElevation, float width, float phase,
                           float animationTime, vec3 lowColor, vec3 highColor) {
    vec2 sideAxis = vec2(-axis.y, axis.x);
    float along = dot(horizontal, axis);
    float across = dot(horizontal, sideAxis);

    float slowTime = animationTime * 0.0065;
    vec2 flowPosition = vec2(across * 1.42 + along * 0.36,
                             along * 1.18 + elevation * 0.54 + phase);
    float flowNoise = getAuroraFlowNoise(flowPosition * 1.55, slowTime,
                                         vec2(0.082, -0.037));

    float longWave = sin(across * 2.65 + along * 1.17 +
                         slowTime * 0.46 + phase * 2.1);
    float secondaryWave = sin(across * 5.30 - along * 0.73 -
                              slowTime * 0.23 + phase * 3.7);
    float centre = baseElevation + (flowNoise - 0.5) * 0.205 +
                   longWave * 0.048 + secondaryWave * 0.017;

    float distanceToCurtain = abs(elevation - centre);
    float body = 1.0 - smoothstep(width * 0.38, width, distanceToCurtain);
    float innerFold = 1.0 - smoothstep(width * 0.10, width * 0.43,
                                       distanceToCurtain);
    float feather = 1.0 - smoothstep(width * 0.72, width * 1.85,
                                     distanceToCurtain);

    // Broad-scale modulation keeps the curtain organic without separating it
    // into isolated ribbons or evenly spaced strips.
    float densityDrift = 0.70 + flowNoise * 0.30;
    body *= densityDrift;
    innerFold *= 0.58 + flowNoise * 0.42;

    // Fine vertical rays are restricted to the curtain and fade upward. They
    // use smooth periodic structure disturbed by the existing flow field.
    float rayCoordinate = across * 28.0 + along * 4.3 +
                          flowNoise * 7.0 - slowTime * 0.31 + phase * 9.0;
    float rayWave = sin(rayCoordinate) * 0.5 + 0.5;
    rayWave *= sin(rayCoordinate * 0.47 + 1.9) * 0.5 + 0.5;
    float rays = smoothstep(0.45, 0.88, rayWave);
    float upwardDistance = max(elevation - centre, 0.0) / max(width, 1.0e-4);
    float rayHeight = (1.0 - smoothstep(0.18, 2.55, upwardDistance)) *
                      smoothstep(-0.16, 0.14, elevation - centre);
    rays *= rayHeight * feather * 0.22;

    float colourHeight = saturate((elevation - centre + width) /
                                  max(width * 2.35, 1.0e-4));
    float colourFlow = saturate(colourHeight * 0.70 + flowNoise * 0.30);
    vec3 layerColor = mix(lowColor, highColor, smoothCubic(colourFlow));

    float density = body * 0.66 + innerFold * 0.48 + rays;
    float skyGlow = feather * (0.040 + innerFold * 0.028);
    vec3 weightedColor = layerColor * density +
                         mix(lowColor, highColor, 0.56) * skyGlow;
    return vec4(weightedColor, density + skyGlow);
}

vec3 getOverworldAurora(vec3 direction, float animationTime, int worldDay,
                         float nightVisibility, float rain,
                         float transitionTime) {
    if (nightVisibility <= 0.0 || direction.y <= 0.015) return vec3(0.0);

    float eventGate = getAuroraEventGate(worldDay, transitionTime);
    if (eventGate <= 0.0) return vec3(0.0);

    // Clear-weather fade preserves smooth transitions while guaranteeing that
    // established rain and thunder conditions contain no aurora contribution.
    float clearWeather = 1.0 - smoothstep(0.0, 0.025, saturate(rain));
    if (clearWeather <= 0.0) return vec3(0.0);

    const vec3 deepEmerald = vec3(0.025, 0.230, 0.115);
    const vec3 green = vec3(0.045, 0.335, 0.165);
    const vec3 turquoise = vec3(0.055, 0.290, 0.275);
    const vec3 softCyan = vec3(0.070, 0.225, 0.315);
    const vec3 subtleBlue = vec3(0.050, 0.135, 0.255);

    vec2 horizontal = direction.xz / max(length(direction.xz), 1.0e-4);
    float elevation = saturate(direction.y);

    // Three overlapping heights and orientations provide convincing parallax-
    // like depth without ray marching, loops, texture reads, or extra passes.
    vec4 backCurtain = getAuroraCurtainLayer(
        horizontal, elevation, vec2(0.907, 0.419), 0.63, 0.205, 1.73,
        animationTime, subtleBlue, softCyan);
    vec4 middleCurtain = getAuroraCurtainLayer(
        horizontal, elevation, vec2(-0.340, 0.940), 0.43, 0.178, 4.11,
        animationTime * 0.91, turquoise, softCyan);
    vec4 frontCurtain = getAuroraCurtainLayer(
        horizontal, elevation, vec2(0.661, -0.751), 0.265, 0.145, 6.37,
        animationTime * 1.07, deepEmerald, green);

    vec3 weightedColor = backCurtain.rgb * 0.48 +
                         middleCurtain.rgb * 0.72 +
                         frontCurtain.rgb * 0.88;
    float totalDensity = backCurtain.a * 0.48 +
                         middleCurtain.a * 0.72 +
                         frontCurtain.a * 0.88;

    // Soft compression preserves internal gradients at intersections and keeps
    // stars visible through the additive sky-only aurora contribution.
    float densityResponse = totalDensity / (1.0 + totalDensity * 0.62);
    vec3 blendedColor = weightedColor / max(totalDensity, 1.0e-4);
    float horizonFade = smoothstep(0.025, 0.16, direction.y);
    float upperFade = 1.0 - smoothstep(0.94, 1.0, direction.y);
    float visibility = nightVisibility * clearWeather * horizonFade * upperFade;

    return blendedColor * densityResponse * visibility * 0.145;
}

#endif
