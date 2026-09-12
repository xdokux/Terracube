#version 120
#define WavingPlantsSpeed 0.2
#define WavingLeavesSpeed 0.07

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

uniform sampler2D noisetex;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform float frameTimeCounter;
uniform float rainStrength;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 wPos;
varying vec2 uv0;
varying vec2 uv1;
varying float flag1, flag2, flag3, flag4, flag5, flag6, flag7;
varying vec4 positionInViewCoord;

void main() {
    positionInViewCoord = gl_ModelViewMatrix * gl_Vertex;
    gl_Position = gbufferProjection * positionInViewCoord;
    vec4 position = gl_Vertex;
    vec4 pos = gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex;

    // Removed waving effect for plants and leaves

    position = gl_ModelViewMatrix * position;
    gl_Position = gl_ProjectionMatrix * position;
    gl_FogFragCoord = length(position.xyz);
    
    flag1 = (mc_Entity.x == 56.0) ? 1.0 : 0.0;
    flag2 = (mc_Entity.x == 73.0) ? 1.0 : 0.0;
    flag3 = (mc_Entity.x == 129.0) ? 1.0 : 0.0;
    flag4 = (mc_Entity.x == 14.0) ? 1.0 : 0.0;
    flag5 = (mc_Entity.x == 15.0) ? 1.0 : 0.0;
    flag6 = (mc_Entity.x == 21.0) ? 1.0 : 0.0;
    flag7 = (mc_Entity.x == 74.0) ? 1.0 : 0.0;

    glcolor = gl_Color;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    uv0 = gl_MultiTexCoord0.xy;
    uv1 = gl_MultiTexCoord1.xy;
    wPos = pos.xyz;
}
