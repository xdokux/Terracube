#version 120

uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;
uniform vec2 mc_Entity;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 viewPos;
varying vec3 worldNormal;
varying float isWater;

void main() {
    vec4 pos = gl_ModelViewMatrix * gl_Vertex;

    isWater = (mc_Entity.x == 8.0 || mc_Entity.x == 9.0) ? 1.0 : 0.0;

    if (isWater > 0.5) {
        pos.y += sin(frameTimeCounter * 1.2 + gl_Vertex.x * 1.0 + gl_Vertex.z * 1.0) * 0.02;
    }

    viewPos  = pos.xyz;

    gl_Position = gl_ProjectionMatrix * pos;
    texcoord    = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord     = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor     = gl_Color;
    worldNormal = (gbufferModelViewInverse * vec4(gl_NormalMatrix * gl_Normal, 0.0)).xyz;
}