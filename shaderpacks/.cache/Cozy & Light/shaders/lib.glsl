uniform float rainStrength;
uniform vec3 sunPosition;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 cameraPosition;
uniform mat4 modelViewMatrix;
uniform vec3 chunkOffset;
uniform vec3 shadowLightPosition;
uniform float near, far;
uniform vec3 fogColor;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;

float inCave = 1.0 - float(eyeBrightnessSmooth.y)/240;
vec3 eyeCameraPosition = cameraPosition + gbufferModelViewInverse[3].xyz;

const vec3 specularColor = vec3(1.0, 1.0, 1.0);
const float specularIntensity = 0.2;
const float specularExp = 5.0;

const vec3 blockLightColor = vec3(10.0, 3.0, 1.0);
const vec3 blockLightTint = vec3(1.5, 0.8, 0.2);
//const vec3 blockLightColor = vec3(1.8, 1.2, 1.0);
const vec3 shadowColor = vec3(0.1, 0.2, 0.2);
const vec3 lmShadowColor = vec3(0.0, 0.0, 0.0);
const vec3 nightColor = vec3(0.01, 0.02, 0.1);
const vec3 sunsetOrange = vec3(1.0, 0.1, -0.2);
const vec3 sunsetYellow = vec3(0.5, 0.1, -0.1);
const vec3 caveFogColor = vec3(0.2, 0.25, 0.3);
const vec3 caveFogDensities = vec3(0.4, 0.5, 0.7);
const vec3 lavaFogColor = vec3(1.0, 0.1, 0.0);
const vec3 snowFogColor = vec3(0.9, 0.9, 1.0);
const float lavaFogDen = 0.5;
const float snowFogDen = 0.5;

const vec3 waterTint = vec3(0.1, 0.2, 0.5);

// Direction from a given point to camera in feet player space
vec3 GetCameraDirection(vec3 feetPlayerPos) {
    return normalize(-feetPlayerPos);
}

// Sun's direction in feet player space
vec3 GetSunDirection() {
    return normalize((gbufferModelViewInverse * vec4(sunPosition, 1.0)).xyz);
}

// 1 -> sun is up, 0 -> sun is down
float GetSunVisibility() {
    vec3 sunDirection = GetSunDirection();
    float sunVis = clamp((dot(sunDirection, vec3(0, 1, 0)) + 0.3) * 1.0, 0.0, 1.0);
    return sunVis;
}

// Sun/Moon's direction in feet player space
vec3 GetShadowLightDirection() {
    return normalize((gbufferModelViewInverse * vec4(shadowLightPosition, 1.0)).xyz);
}

// Shadow brightness after accounting for block light levels, day/night and rain
float ShadowBrightnessAdjusted(float lmx) {
    float adjusted = mix(0.4, 0.0, GetSunVisibility());
    adjusted = mix(adjusted, 1.0, rainStrength);
    return mix(adjusted, 1.0, lmx);
}

// Simple specular highlights
float PhongSpecular(float intensity, float exponent, vec3 camDir, vec3 lightDir, vec3 normal) {

    float specular = clamp(dot(normalize(camDir + lightDir), normal), 0.0, 1.0);
    specular = pow(specular, exponent) * intensity;

    return specular;
}

// Dynamic shadowlight (sun/moon) color depending on daytime, rain, etc
vec3 GetShadowLightColor(float sunVis, float rain) {
    vec3 dayCol = vec3(0.0, 0.2667, 0.4118);
    vec3 sunsetCol = vec3(4.0, 3.5, 1.7);
    vec3 nightCol = vec3(1.0, 1.05, 1.2);
    vec3 rainCol = vec3(1.0, 1.0, 1.0);

    vec3 col = vec3(0.0);

    if(sunVis >= 0.5)
    {
        col = mix(sunsetCol, dayCol, sunVis * 2.0 - 1.0);
    } else
    {
        col = mix(nightCol, sunsetCol, sunVis * 2.0);
    }

    col = mix(col, rainCol, rain);

    return col;
}

// Dynamic sky color depending on daytime, rain, etc
vec3 GetSkyColor(float sunVis, float rain) {
    vec3 dayCol = vec3(0.1, 0.4, 1.0);
    vec3 sunsetCol = vec3(0.2, 0.2, 0.8);
    vec3 nightCol = vec3(0.0, 0.005, 0.02);
    vec3 dayRainCol = vec3(0.05, 0.06, 0.1);
    vec3 nightRainCol = vec3(0.0, 0.005, 0.02);

    vec3 col = vec3(0.0);

    if(sunVis >= 0.5)
    {
        col = mix(sunsetCol, dayCol, sunVis * 2.0 - 1.0);
    } else
    {
        col = mix(nightCol, sunsetCol, sunVis * 2.0);
    }

    vec3 rainCol = mix(nightRainCol, dayRainCol, sunVis);

    col = mix(col, rainCol, rain);

    return col;
}

// Dynamic sky light color depending on daytime, rain, etc
vec3 GetLightColor(float sunVis, float rain, int underwater) {
    vec3 dayCol = vec3(1.0, 1.2, 1.4);
    vec3 sunsetCol = vec3(1.0, 0.8, 0.3);
    vec3 nightCol = vec3(0.2, 0.25, 0.3);
    vec3 dayRainCol = vec3(0.25, 0.28, 0.35);
    vec3 nightRainCol = vec3(0.1, 0.12, 0.19);
    vec3 dayWaterCol = vec3(0.0, 0.3, 0.6);
    vec3 nightWaterCol = vec3(0.0, 0.0, 0.02);

    vec3 light = vec3(0.0);

    if(sunVis >= 0.5)
    {
        light = mix(sunsetCol, dayCol, sunVis * 2.0 - 1.0);
    } else
    {
        light = mix(nightCol, sunsetCol, sunVis * 2.0);
    }

    vec3 rainCol = mix(nightRainCol, dayRainCol, sunVis);

    light = mix(light, rainCol, rain);

    light = mix(light, nightCol, inCave);

    if(underwater == 1) {
        light = mix(nightWaterCol, dayWaterCol, sunVis * (1.0 - inCave));
    }

    return light;
}

// Dynamic fog densities depending on daytime, rain, etc
vec3 GetFogDensities(float sunVis, float rain, int underwater) {
    vec3 dayDen = vec3(0.8, 0.8, 1.0);
    vec3 sunsetDen = vec3(0.9, 0.6, 1.1);
    vec3 nightDen = vec3(0.4, 0.5, 0.7);
    vec3 rainDen = vec3(5.0, 4.5, 5.0);
    vec3 waterDen = vec3(12.0, 8.0, 10.0);

    vec3 fog = vec3(0.0);

    if(sunVis >= 0.5)
    {
        fog = mix(sunsetDen, dayDen, sunVis * 2.0 - 1.0);
    } else
    {
        fog = mix(nightDen, sunsetDen, sunVis * 2.0);
    }

    fog = mix(fog, rainDen, rain);

    fog = mix(fog, nightDen, inCave);

    if(underwater == 1) {
        fog = waterDen;
    }

    return fog;
}

float fogify(float x, float w) {
	return w / (x * x + w);
}

vec3 calcSkyColor(vec3 pos) {
	float upDot = dot(pos, gbufferModelView[1].xyz); //not much, what's up with you?
	float sunDot = dot(normalize(pos), normalize(sunPosition));
	float sunVis = GetSunVisibility();

	vec3 lightCol = GetLightColor(sunVis, rainStrength, isEyeInWater);
	vec3 fogDensities = GetFogDensities(sunVis, rainStrength, isEyeInWater);
	vec3 skyFogColor = mix(lightCol, GetSkyColor(sunVis, rainStrength), exp(-fogDensities));

	vec3 sky = mix(GetSkyColor(sunVis, rainStrength), skyFogColor, fogify(max(upDot, 0.0), 0.25));

	float sunset = 1.0 - 2.0 * abs(sunVis - 0.5);
	sunset *= 1.0 - rainStrength;

	sky += sunsetOrange * vec3(exp((sunDot - 1.0) * 1.0)) * sunset;

	sky += sunsetYellow * vec3(exp((sunDot - 1.0) * 7.0)) * sunset;
	
	return sky;
}

// ---------------------------------------------- Coordinate space conversions ----------------------------------------------


vec3 ModelPosToViewPos(vec3 modelPos) {
    return (gl_ModelViewMatrix * vec4(modelPos, 1.0)).xyz;
}

vec3 PlayerPosToViewPos(vec3 playerPos) {
    return (gbufferModelView * vec4(playerPos, 1.0)).xyz;
}

vec3 ViewPosToPlayerPos(vec3 viewPos) {
    return (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
}

vec3 EyePosToViewPos(vec3 eyePos) {
    return mat3(gbufferModelView) * eyePos;
}

vec3 ViewPosToEyePos(vec3 viewPos) {
    return mat3(gbufferModelViewInverse) * viewPos;
}

vec3 EyePosToWorldPos(vec3 eyePos) {
    return eyePos + eyeCameraPosition;
}

vec3 WorldPosToEyePos(vec3 worldPos) {
    return worldPos - eyeCameraPosition;
}

vec3 WorldPosToViewPos(vec3 worldPos) {
    return mat3(gbufferModelView) * (worldPos - cameraPosition);
}

vec3 ViewPosToWorldPos(vec3 viewPos) {
    return mat3(gbufferModelViewInverse) * viewPos + cameraPosition;
}

vec4 ViewPosToClipPos(vec3 viewPos) {
    return gbufferProjection * vec4(viewPos, 1.0);
}

vec3 ClipPosToViewPos(vec4 clipPos) {
    return (gbufferProjectionInverse * clipPos).xyz;
}

vec3 ClipPosToNdcPos(vec4 clipPos) {
    return clipPos.xyz / clipPos.w;
}

vec3 NdcPosToScreenPos(vec3 ndcPos) {
    return ndcPos * 0.5 + 0.5;
}

vec3 ScreenPosToNdcPos(vec3 screenPos) {
    return screenPos * 2.0 - 1.0;
}

vec3 ViewPosToScreenPos(vec3 viewPos) {
    vec4 clip = gbufferProjection * vec4(viewPos, 1.0);
    return (clip.xyz / clip.w) * 0.5 + 0.5;
}

vec3 ScreenPosToViewPos(vec3 screenPos) {
    vec3 ndc = screenPos * 2.0 - 1.0;
    vec4 homogeneous = gbufferProjectionInverse * vec4(ndc, 1.0);
    return homogeneous.xyz / homogeneous.w;
}
