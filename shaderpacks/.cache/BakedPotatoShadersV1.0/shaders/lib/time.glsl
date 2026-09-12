#ifndef CINDERLIGHT_TIME_GLSL
#define CINDERLIGHT_TIME_GLSL

#include "/lib/math.glsl"

uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform float rainStrength;
uniform int worldTime;

vec3 getSunDirection() {
    return safeNormalize(mat3(gbufferModelViewInverse) * sunPosition);
}

vec3 getMoonDirection() {
    return safeNormalize(mat3(gbufferModelViewInverse) * moonPosition);
}

vec3 getShadowLightDirection() {
    return safeNormalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
}

float getDayAmount(vec3 sunDirection) {
    return smoothstep(-0.10, 0.12, sunDirection.y);
}

float getDayAmount() {
    return getDayAmount(getSunDirection());
}

float getNightAmount() {
    return 1.0 - getDayAmount();
}

float getTwilightAmount(vec3 sunDirection) {
    return 1.0 - smoothstep(0.025, 0.30, abs(sunDirection.y));
}

float getTwilightAmount() {
    return getTwilightAmount(getSunDirection());
}

float getSunriseSunsetFacing(vec3 direction, vec3 sunDirection) {
    vec2 a = normalize(direction.xz + vec2(1.0e-5));
    vec2 b = normalize(sunDirection.xz + vec2(1.0e-5));
    float facing = max(dot(a, b), 0.0);
    return square(square(facing));
}

float getSunriseSunsetFacing(vec3 direction) {
    return getSunriseSunsetFacing(direction, getSunDirection());
}

float getTimeOfDayNormalized() {
    return mod(float(worldTime), 24000.0) * (1.0 / 24000.0);
}

float getCyclicTimeDistance(float timeOfDay, float center) {
    float distanceToCenter = abs(timeOfDay - center);
    return min(distanceToCenter, 1.0 - distanceToCenter);
}

float getCyclicTimePhase(float timeOfDay, float center, float innerRadius, float outerRadius) {
    return 1.0 - smoothstep(innerRadius, outerRadius,
                            getCyclicTimeDistance(timeOfDay, center));
}

float getCyclicTimePhase(float center, float innerRadius, float outerRadius) {
    return getCyclicTimePhase(getTimeOfDayNormalized(), center, innerRadius, outerRadius);
}

float getSunrisePhaseAmount(float timeOfDay) {
    return getCyclicTimePhase(timeOfDay, 0.0125, 0.0225, 0.0750);
}

float getSunrisePhaseAmount() {
    return getSunrisePhaseAmount(getTimeOfDayNormalized());
}

float getSunsetPhaseAmount(float timeOfDay) {
    return getCyclicTimePhase(timeOfDay, 0.5050, 0.0225, 0.0825);
}

float getSunsetPhaseAmount() {
    return getSunsetPhaseAmount(getTimeOfDayNormalized());
}

void getAtmosphereState(out vec4 temporalState, out vec4 sunState, out vec3 moonDirection) {
    float timeOfDay = getTimeOfDayNormalized();
    vec3 sunDirection = getSunDirection();
    float day = getDayAmount(sunDirection);
    moonDirection = vec3(0.0);
    if (day < 1.0) moonDirection = getMoonDirection();
    temporalState = vec4(timeOfDay, day, getTwilightAmount(sunDirection),
                         getSunrisePhaseAmount(timeOfDay));
    sunState = vec4(sunDirection, getSunsetPhaseAmount(timeOfDay));
}

#endif
