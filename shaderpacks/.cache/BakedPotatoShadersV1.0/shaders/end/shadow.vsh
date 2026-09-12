#version 120

#include "/lib/settings.glsl"
#include "/lib/waving.glsl"
#include "/lib/water_waves.glsl"

attribute vec2 mc_Entity;
attribute vec4 mc_midTexCoord;

uniform mat4 shadowModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

varying vec2 vTexCoord;
varying vec4 vColor;

const float CINDERLIGHT_SHADOW_DISTORTION = 0.86;

void main() {
    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec3 playerPosition = (shadowModelViewInverse * viewPosition).xyz;
    vec2 baseTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 middleTexCoord = (gl_TextureMatrix[0] * mc_midTexCoord).xy;
    float topVertexWeight = step(baseTexCoord.y, middleTexCoord.y);
    playerPosition = applyFoliageWaving(playerPosition, mc_Entity.x, topVertexWeight);

    vec3 normalWorld = normalize(mat3(shadowModelViewInverse) * (gl_NormalMatrix * gl_Normal));
    if (isWaterMaterial(mc_Entity.x) && normalWorld.y > 0.45) {
        vec3 worldPosition = playerPosition + cameraPosition;
        playerPosition.y += getWaterWaveHeight(worldPosition.xz);
    }

    vec4 shadowPosition = shadowProjection * shadowModelView * vec4(playerPosition, 1.0);
    float distortion = (1.0 - CINDERLIGHT_SHADOW_DISTORTION) + length(shadowPosition.xy) * CINDERLIGHT_SHADOW_DISTORTION;
    shadowPosition.xy /= distortion;
    shadowPosition.z *= 0.5;

    vTexCoord = baseTexCoord;
    vColor = gl_Color;
    gl_Position = shadowPosition;
}
