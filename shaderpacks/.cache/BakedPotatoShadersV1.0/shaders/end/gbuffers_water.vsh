#version 120

#include "/lib/settings.glsl"
#include "/lib/materials.glsl"
#include "/lib/water_waves.glsl"

attribute vec2 mc_Entity;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;

varying vec2 vTexCoord;
varying vec2 vLightmapCoord;
varying vec4 vColor;
varying vec3 vNormalWorld;
varying vec3 vPlayerPosition;
varying vec3 vWorldPosition;
varying float vIsWater;
varying float vMaterialId;

void main() {
    vec4 originalViewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec3 playerPosition = (gbufferModelViewInverse * originalViewPosition).xyz;
    vec3 normalWorld = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal));
    float water = isWaterMaterial(mc_Entity.x) ? 1.0 : 0.0;
    vec3 worldPosition = playerPosition + cameraPosition;

    if (water > 0.5 && normalWorld.y > 0.45) {
        playerPosition.y += getWaterWaveHeight(worldPosition.xz);
        worldPosition.y = playerPosition.y + cameraPosition.y;
    }

    vPlayerPosition = playerPosition;
    vWorldPosition = worldPosition;
    vNormalWorld = normalWorld;
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightmapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;
    vIsWater = water;
    vMaterialId = mc_Entity.x;
    gl_Position = gbufferProjection * gbufferModelView * vec4(playerPosition, 1.0);
}
