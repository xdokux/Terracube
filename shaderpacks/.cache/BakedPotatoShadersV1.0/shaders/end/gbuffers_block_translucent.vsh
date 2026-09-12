#version 120

#define CINDERLIGHT_LIGHTING_STATE_ONLY
#include "/lib/end_lighting.glsl"
#undef CINDERLIGHT_LIGHTING_STATE_ONLY

varying vec2 vTexCoord;
varying vec2 vLightmapCoord;
varying vec4 vColor;
varying vec3 vNormalWorld;
varying vec3 vPlayerPosition;
varying vec4 vLightingState0;
varying vec4 vLightingState1;

void main() {
    getLightingState(vLightingState0, vLightingState1);
    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vPlayerPosition = (gbufferModelViewInverse * viewPosition).xyz;
    vNormalWorld = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal));
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightmapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
