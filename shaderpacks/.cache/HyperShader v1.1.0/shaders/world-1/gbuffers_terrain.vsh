#version 120

/* gbuffers_terrain.vsh (NETHER) — versión simple: solo lava ondulante + datos
   para iluminar con el LIGHTMAP vanilla en el fragment (sin sombras = sin grano). */

#include "/lib/common.glsl"
#include "/lib/noise.glsl"

attribute vec4 mc_Entity;

uniform mat4  gbufferModelView;
uniform mat4  gbufferModelViewInverse;
uniform vec3  cameraPosition;
uniform float frameTimeCounter;

varying vec2  texcoord;
varying vec2  lmcoord;
varying vec4  vColor;
varying vec3  worldPos;
varying float matID;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    vec4 vs = gl_ModelViewMatrix * gl_Vertex;
    worldPos = (gbufferModelViewInverse * vs).xyz + cameraPosition;

    matID = (mc_Entity.x == ID_LAVA) ? 0.25 : 0.0;
    if (matID == 0.25) {
        float n = fbm(worldPos.xz * 0.6 + frameTimeCounter * LAVA_FLOW_SPEED, 3);
        worldPos.y += (n - 0.5) * 0.10;
        vs = gbufferModelView * vec4(worldPos - cameraPosition, 1.0);
    }

    gl_Position = gl_ProjectionMatrix * vs;
}
