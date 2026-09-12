#version 120
#include "/lib/settings.glsl"

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 normalV;
varying vec3 viewPos;
varying vec3 worldPos;
varying float isWater;

attribute vec4 mc_Entity;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelViewInverse;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor  = gl_Color;
    normalV  = normalize(gl_NormalMatrix * gl_Normal);
    viewPos  = (gl_ModelViewMatrix * gl_Vertex).xyz;
    worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
    isWater  = float(mc_Entity.x == 10008.0);
}
