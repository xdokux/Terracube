uniform int worldTime;

const int times[7] = int[](0, 6000, 11500, 12785, 18000, 23215, 24000);

const vec3 skyTopColor[4] = vec3[](
    vec3(0.1, 0.2, 0.5) * 1.5,
    vec3(0.1, 0.13, 0.2) * 3.2,
    vec3(0.2, 0.24, 0.4) * 1.3,
    vec3(0.04, 0.06, 0.1) * 2.5
);

const vec3 skyMiddleColor[4] = vec3[](
    vec3(0.25, 0.45, 0.85) * 1.8,
    vec3(0.4, 0.65, 1.0) * 1.4,
    vec3(0.5, 0.4, 0.5) * 1.4,
    vec3(0.07, 0.09, 0.1) * 4.0
);

const vec3 skyHorizonColor[4] = vec3[](
    vec3(0.7, 0.8, 1.0) * 1.2,
    vec3(0.9, 0.95, 1.05) * 1.1,
    vec3(1.0, 0.55, 0.3) * 1.3,
    vec3(1.02, 1.05, 1.2) * 0.35
);

const vec3 skyLightColor[4] = vec3[](
    vec3(0.2, 0.25, 0.3) * 3.0,
    vec3(0.35, 0.45, 0.55) * 3.0,
    vec3(0.18, 0.15, 0.22) * 1.8,
    vec3(0.08, 0.1, 0.18) * 1.4
);

const vec3 pointLightColor[4] = vec3[](
    vec3(3.0, 1.8, 0.5) * 0.8,
    vec3(2.0, 1.5, 1.0) * 1.0,
    vec3(1.0, 0.25, 0.0) * 1.2,
    vec3(0.2, 0.2, 0.3) * 0.8
);

const vec3 pointMieColor[4] = vec3[](
    vec3(3.0, 1.0, 0.2) * 3.0,
    vec3(1.0, 0.8, 0.6),
    vec3(1.0, 0.5, 0.1) * 4.0,
    vec3(0.4, 0.3, 0.7) * 0.5
);

int timeIndex;
float timeBlend;

float getPointLightBlackout() {
    float r1 = clamp(1.0 - abs(float(worldTime - 12785)) / 100.0, 0.0, 1.0);
    float r2 = clamp(1.0 - abs(float(worldTime - 23215)) / 100.0, 0.0, 1.0);
    return 1.0 - max(r1, r2);
}

void calculateTimeBlend() {
    int i = int(worldTime < 6000) * 0 +
            int(worldTime >= 6000  && worldTime < 11500) * 1 +
            int(worldTime >= 11500 && worldTime < 12785) * 2 +
            int(worldTime >= 12785 && worldTime < 18000) * 3 +
            int(worldTime >= 18000 && worldTime < 23215) * 4 +
            int(worldTime >= 23215) * 5;

    timeIndex = i;
    float raw = float(worldTime - times[i]) / float(times[i + 1] - times[i]);
    float power = (i >= 4) ? 2.5 : 0.4;
    timeBlend = smoothstep(0.0, 1.0, pow(raw, power));
}

const int ci[6] = int[](0, 1, 0, 2, 3, 2);
const int cn[6] = int[](1, 0, 2, 3, 2, 0);

vec3 getSkyTopColor()     { return mix(skyTopColor[ci[timeIndex]],     skyTopColor[cn[timeIndex]],     timeBlend); }
vec3 getSkyMiddleColor()  { return mix(skyMiddleColor[ci[timeIndex]],  skyMiddleColor[cn[timeIndex]],  timeBlend); }
vec3 getSkyHorizonColor() { return mix(skyHorizonColor[ci[timeIndex]], skyHorizonColor[cn[timeIndex]], timeBlend); }
vec3 getSkyLightColor()   { return mix(skyLightColor[ci[timeIndex]],   skyLightColor[cn[timeIndex]],   timeBlend); }
vec3 getPointLightColor() { return mix(pointLightColor[ci[timeIndex]], pointLightColor[cn[timeIndex]], timeBlend) * getPointLightBlackout(); }
vec3 getPointMieColor()   { return mix(pointMieColor[ci[timeIndex]],   pointMieColor[cn[timeIndex]],   timeBlend); }