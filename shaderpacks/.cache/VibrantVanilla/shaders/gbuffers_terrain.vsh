#version 120
attribute vec4 mc_Entity;
uniform mat4 shadowModelViewMatrix;
uniform mat4 shadowProjectionMatrix;
uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec4 shadowcoord;
varying vec3 viewPos;
void main() {
    vec4 position = gl_Vertex;
    vec4 worldPos = gbufferModelViewInverse * gl_ModelViewMatrix * position;
    bool isPlant = (abs(mc_Entity.x - 10031.0) < 0.5);
    bool isLeaves = (abs(mc_Entity.x - 10032.0) < 0.5);
    if (isPlant || isLeaves) {
        float wave = sin(frameTimeCounter * 3.0 + worldPos.x * 0.8 + worldPos.z * 0.8) * 0.035;
        if (isPlant) {
            if (fract(position.y + 0.01) > 0.02) {
                position.xyz += vec3(wave, wave * 0.4, wave);
            }
        } else {
            position.xyz += vec3(wave, wave * 0.4, wave);
        }
    }
    gl_Position = gl_ModelViewProjectionMatrix * position;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor = gl_Color;
    vec4 vPos = gl_ModelViewMatrix * position;
    viewPos = vPos.xyz;
    vec4 wPos = gbufferModelViewInverse * vPos;
    shadowcoord = shadowProjectionMatrix * shadowModelViewMatrix * wPos;
}
