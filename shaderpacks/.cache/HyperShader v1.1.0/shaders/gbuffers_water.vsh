#version 120

/* gbuffers_water.vsh — Superficie translúcida (agua, HIELO, cristal…).
   PILAR 1: olas de Gerstner SOLO en el agua. El hielo y el cristal NO ondulan
   y se tratan como bloques normales en el fragment (con su textura). */

#include "/lib/common.glsl"
#include "/lib/gerstner.glsl"

attribute vec4 mc_Entity;

uniform mat4  gbufferModelView;
uniform mat4  gbufferModelViewInverse;
uniform vec3  cameraPosition;
uniform float frameTimeCounter;

varying vec2  texcoord;
varying vec2  lmcoord;
varying vec4  vColor;
varying vec3  viewPos;
varying vec3  worldPosW;   // v1.1: posición de mundo (gotas de lluvia, espuma)
varying vec3  waveNormal;
varying float matKind;     // 0 = agua, 1 = hielo, 2 = otros (cristal, etc.)

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    vec4 viewSpace = gl_ModelViewMatrix * gl_Vertex;
    vec3 worldPos  = (gbufferModelViewInverse * viewSpace).xyz + cameraPosition;

    float ent = mc_Entity.x;
    matKind = (ent == ID_WATER) ? 0.0 : ((ent == ID_ICE) ? 1.0 : ((ent == ID_PORTAL) ? 3.0 : 2.0));

    vec3 nWorld = vec3(0.0, 1.0, 0.0);
    if (matKind < 0.5) {                       // solo el AGUA ondula
        vec3 disp = gerstnerSurface(worldPos.xz, frameTimeCounter, nWorld);
        worldPos += disp;
        viewSpace = gbufferModelView * vec4(worldPos - cameraPosition, 1.0);
    }

    worldPosW  = worldPos;
    waveNormal = normalize(mat3(gbufferModelView) * nWorld);
    viewPos    = viewSpace.xyz;
    gl_Position = gl_ProjectionMatrix * viewSpace;
}
