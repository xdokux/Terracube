uniform float sunAngle;

const float times[9] = float[](
    0.0, 0.05, 0.25, 0.45, 0.5, 0.51, 0.75, 0.99, 1.0
);

const int colorFrom[8] = int[](2, 0, 1, 0, 2, 3, 4, 3);
const int colorTo[8]   = int[](0, 1, 0, 2, 3, 4, 3, 2);

const vec3 skyTopColor[5] = vec3[](
    vec3(0.25, 0.4, 0.5) * 1.0,  
    vec3(0.1, 0.15, 0.3) * 2.0,  
    vec3(0.2, 0.24, 0.4) * 1.3,  
    vec3(0.1, 0.11, 0.2) * 0.8,  
    vec3(0.04, 0.05, 0.3) * 0.3
);

const vec3 skyMiddleColor[5] = vec3[](
    vec3(0.35, 0.5, 0.5) * 2.0,
    vec3(0.6, 0.9, 1.2) * 1.5,
    vec3(0.7, 0.6, 0.6) * 1.4,
    vec3(0.2, 0.4, 0.4) * 0.6,
    vec3(0.07, 0.15, 0.3) * 1.0
);

const vec3 skyHorizonColor[5] = vec3[](
    vec3(1.0, 0.9, 0.75) * 1.2,
    vec3(1.05, 1.0, 1.05) * 1.1,
    vec3(1.0, 0.6, 0.4) * 1.3,
    vec3(0.8, 0.8, 0.9) * 0.2,
    vec3(1.0, 1.1, 1.2) * 0.1
);

const vec3 skyLightColor[5] = vec3[](
    vec3(0.15, 0.17, 0.2) * 3.0,
    vec3(0.3, 0.35, 0.5) * 1.0,
    vec3(0.13, 0.1, 0.16) * 2.0,
    vec3(0.12, 0.14, 0.2) * 0.8,
    vec3(0.0, 0.06, 0.20) * 0.3
);

const vec3 pointLightColor[5] = vec3[](
    vec3(2.7, 1.7, 0.7) * 0.3 * 2.0,
    vec3(2.2, 1.5, 1.0) * 0.3 * 2.0,
    vec3(1.0, 0.25, 0.0) * 0.5 * 2.0,
    vec3(1.3, 1.1, 0.7) * 0.05 * 2.0,
    vec3(0.16, 0.19, 0.2) * 0.15 * 2.0
);

const vec3 pointMieColor[5] = vec3[](
    vec3(3.0, 1.0, 0.2) * 0.5 * 1.5,
    vec3(1.0, 0.8, 0.6) * 1.5,
    vec3(1.0, 0.5, 0.1) * 1.5,
    vec3(1.0, 1.0, 1.5) * 0.2 * 1.5,
    vec3(0.4, 0.4, 0.4) * 0.5 * 1.5
);

const vec3 rayColor[5] = vec3[](
    vec3(3.0, 1.5, 0.2) * 0.5,
    vec3(1.0, 0.8, 0.6) * 0.5,
    vec3(1.0, 0.5, 0.1) * 1.5,
    vec3(5.0, 1.5, 0.2) * 0.0,
    vec3(0.4, 0.4, 0.4) * 0.0
);

int timeIndex;
float timeBlend;

float getPointLightBlackout() {
    float t = fract(sunAngle);
    float d1 = abs(t - 0.5);
    float d2 = min(t, 1.0 - t);
    float r1 = clamp(1.0 - d1 / 0.004, 0.0, 1.0);
    float r2 = clamp(1.0 - d2 / 0.004, 0.0, 1.0);
    return 1.0 - max(r1, r2);
}

void calculateTimeBlend() {
    timeIndex = 7;
    timeBlend = 1.0;
    float angle = fract(sunAngle); 
    
    for (int i = 0; i < 8; i++) {
        if (angle >= times[i] && angle < times[i + 1]) {
            timeIndex = i;
            float a = times[i];
            float b = times[i + 1];
            timeBlend = clamp((angle - a) / (b - a), 0.0, 1.0);
            return;
        }
    }
}

vec3 getSkyTopColor() {
    return mix(skyTopColor[colorFrom[timeIndex]], skyTopColor[colorTo[timeIndex]], timeBlend);
}

vec3 getSkyMiddleColor() {
    return mix(skyMiddleColor[colorFrom[timeIndex]], skyMiddleColor[colorTo[timeIndex]], timeBlend);
}

vec3 getSkyHorizonColor() {
    return mix(skyHorizonColor[colorFrom[timeIndex]], skyHorizonColor[colorTo[timeIndex]], timeBlend);
}

vec3 getSkyLightColor() {
    return mix(skyLightColor[colorFrom[timeIndex]], skyLightColor[colorTo[timeIndex]], timeBlend);
}

vec3 getPointLightColor() {
    return mix(pointLightColor[colorFrom[timeIndex]], pointLightColor[colorTo[timeIndex]], timeBlend) * getPointLightBlackout();
}

vec3 getPointMieColor() {
    return mix(pointMieColor[colorFrom[timeIndex]], pointMieColor[colorTo[timeIndex]], timeBlend);
}

vec3 getRayColor() {
    return mix(rayColor[colorFrom[timeIndex]], rayColor[colorTo[timeIndex]], timeBlend);
}