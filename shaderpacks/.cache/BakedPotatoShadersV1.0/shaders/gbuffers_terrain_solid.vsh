#version 120

#define CINDERLIGHT_LIGHTING_STATE_ONLY
#include "/lib/lighting.glsl"
#undef CINDERLIGHT_LIGHTING_STATE_ONLY
#include "/lib/waving.glsl"

attribute vec2 mc_Entity;
attribute vec4 mc_midTexCoord;

uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;

varying vec2 vTexCoord;
varying vec2 vLightmapCoord;
varying vec4 vColor;
varying vec3 vNormalWorld;
varying vec3 vPlayerPosition;
varying vec4 vLightingState0;
varying vec4 vLightingState1;

void main() {
    getLightingState(vLightingState0, vLightingState1);
    vec4 originalViewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec3 playerPosition = (gbufferModelViewInverse * originalViewPosition).xyz;
    vec2 baseTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 middleTexCoord = (gl_TextureMatrix[0] * mc_midTexCoord).xy;
    float topVertexWeight = step(baseTexCoord.y, middleTexCoord.y);
    playerPosition = applyFoliageWaving(playerPosition, mc_Entity.x, topVertexWeight);

    vPlayerPosition = playerPosition;
    vNormalWorld = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal));
    vTexCoord = baseTexCoord;
    vLightmapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;
    gl_Position = gbufferProjection * gbufferModelView * vec4(playerPosition, 1.0);
}
