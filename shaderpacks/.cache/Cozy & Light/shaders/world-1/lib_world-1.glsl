uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 cameraPosition;
uniform mat4 modelViewMatrix;
uniform vec3 chunkOffset;
uniform float near, far;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform int isEyeInWater;

vec3 eyeCameraPosition = cameraPosition + gbufferModelViewInverse[3].xyz;

const vec3 blockLightColor = vec3(10.0, 3.0, 1.0);
const vec3 blockLightTint = vec3(1.5, 0.8, 0.2);
//const vec3 blockLightColor = vec3(1.8, 1.2, 1.0);
const vec3 shadowColor = vec3(0.2, 0.2, 0.3);
const vec3 lmShadowColor = vec3(0.1, 0.0, 0.0);
const vec3 lavaFogColor = vec3(1.0, 0.1, 0.0);
const vec3 snowFogColor = vec3(0.9, 0.9, 1.0);
const float lavaFogDen = 0.5;
const float snowFogDen = 0.5;

// Direction from a given point to camera in feet player space
vec3 GetCameraDirection(vec3 feetPlayerPos) {
    return normalize(-feetPlayerPos);
}

// Simple specular highlights
float PhongSpecular(float intensity, float exponent, vec3 camDir, vec3 lightDir, vec3 normal) {

    float specular = clamp(dot(normalize(camDir + lightDir), normal), 0.0, 1.0);
    specular = pow(specular, exponent) * intensity;

    return specular;
}

// Dynamic sky color depending on daytime, rain, etc
vec3 GetSkyColor() {
    return pow(skyColor, vec3(2.2));
}

// Dynamic sky light color depending on daytime, rain, etc
vec3 GetLightColor() {
    return pow(fogColor, vec3(2.2));
}

// Dynamic fog densities depending on daytime, rain, etc
vec3 GetFogDensities() {

    return vec3(3.0, 3.0, 3.0);
}

vec3 calcSkyColor() {
	return skyColor;
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
