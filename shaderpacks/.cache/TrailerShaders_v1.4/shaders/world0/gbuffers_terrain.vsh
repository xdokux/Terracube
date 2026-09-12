#version 120
#define WavingPlantsSpeed 0.6
#define WavingLeavesSpeed 0.25
#define FoliageWave

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

#ifdef FoliageWave
    // Wave displacement for foliage
    vec3 worldPos = pos.xyz;
    vec3 wave = vec3(0.0);

    bool isLeaves  = (mc_Entity.x == 18.0 || mc_Entity.x == 161.0 || mc_Entity.x == 162.0);
    bool isPlant   = (mc_Entity.x == 31.0 || mc_Entity.x == 37.0 || mc_Entity.x == 38.0 ||
                      mc_Entity.x == 59.0 || mc_Entity.x == 141.0 || mc_Entity.x == 142.0 ||
                      mc_Entity.x == 143.0 || mc_Entity.x == 175.0);
    bool isSapling = (mc_Entity.x == 6.0);
    bool isCane    = (mc_Entity.x == 106.0);

    if (isLeaves) {
        float t = frameTimeCounter * WavingLeavesSpeed * 6.0;
        wave.x = sin(t + worldPos.x * 0.5 + worldPos.z * 0.3) * 0.035;
        wave.z = cos(t * 0.7 + worldPos.x * 0.3 + worldPos.z * 0.5) * 0.025;
    } else if (isPlant) {
        float t = frameTimeCounter * WavingPlantsSpeed * 8.0;
        float h = clamp(gl_MultiTexCoord0.t, 0.0, 1.0);
        wave.x = sin(t + worldPos.x * 0.8 + worldPos.z * 0.6) * 0.05 * h;
        wave.z = cos(t * 0.75 + worldPos.x * 0.4 + worldPos.z * 0.8) * 0.035 * h;
    } else if (isSapling) {
        float t = frameTimeCounter * WavingLeavesSpeed * 10.0;
        wave.x = sin(t + worldPos.x * 0.6 + worldPos.z * 0.4) * 0.03;
        wave.z = cos(t * 0.8 + worldPos.x * 0.4 + worldPos.z * 0.6) * 0.02;
    } else if (isCane) {
        float t = frameTimeCounter * WavingPlantsSpeed * 5.0;
        float h = clamp(gl_Vertex.y + 0.5, 0.0, 1.5) / 1.5;
        wave.x = sin(t + worldPos.x * 0.3 + worldPos.z * 0.7) * 0.06 * h;
        wave.z = cos(t * 0.6 + worldPos.x * 0.7 + worldPos.z * 0.3) * 0.04 * h;
    }

    position.xyz += wave;
#endif

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
