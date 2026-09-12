#version 120

/* gbuffers_terrain.vsh — Bloques opacos sólidos.
   - PILAR 4: base TBN + dirección de vista en tangente (POM/normal map).
   - PILAR 2: deformación viscosa de la lava.
   - VIENTO: ondeo de hojas y plantas (lib/wind.glsl). */

#include "/lib/common.glsl"
#include "/lib/noise.glsl"
#include "/lib/wind.glsl"

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
attribute vec4 at_tangent;        // .xyz tangente, .w handedness

uniform mat4  gbufferModelView;
uniform mat4  gbufferModelViewInverse;
uniform vec3  cameraPosition;
uniform float frameTimeCounter;

varying vec2  texcoord;
varying vec2  lmcoord;
varying vec4  vColor;
varying vec3  viewPos;
varying vec3  worldPos;
varying vec3  viewNormal;
varying mat3  tbn;
varying vec3  viewDirTS;
varying vec2  tileBase;
varying vec2  tileSize;
varying float matID;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    vec4 vs = gl_ModelViewMatrix * gl_Vertex;
    worldPos = (gbufferModelViewInverse * vs).xyz + cameraPosition;

    float entity = mc_Entity.x;
    matID = (entity == ID_LAVA) ? 0.25 : 0.0;
    if (entity == ID_LEAVES || entity == ID_FOLIAGE) matID = 0.15;  // sin POM/normal map

    bool moved = false;

    // PILAR 2: la lava sube/baja muy lento => fluido pesado y viscoso.
    if (matID == 0.25) {
        float n = fbm(worldPos.xz * 0.6 + frameTimeCounter * LAVA_FLOW_SPEED, 3);
        worldPos.y += (n - 0.5) * 0.10;
        moved = true;
    }
#if WAVING == 1
    // VIENTO: hojas (bloque entero) y plantas (la punta se mueve, base fija).
    else if (entity == ID_LEAVES || entity == ID_FOLIAGE) {
        // En Minecraft la V de textura crece hacia ABAJO: V pequeña = parte alta.
        float topMask = (entity == ID_FOLIAGE)
                      ? step(gl_MultiTexCoord0.t, mc_midTexCoord.t)   // 1 = vértice superior
                      : 1.0;                                          // hojas: bloque entero
        float strength = (entity == ID_LEAVES) ? 0.045 : 0.11;
        worldPos += windDisplacement(worldPos, frameTimeCounter, topMask, strength);
        moved = true;
    }
#endif

    if (moved) vs = gbufferModelView * vec4(worldPos - cameraPosition, 1.0);
    viewPos = vs.xyz;

    // --- TBN para PBR / POM ---
    viewNormal     = normalize(gl_NormalMatrix * gl_Normal);
    vec3 tangent   = normalize(gl_NormalMatrix * at_tangent.xyz);
    vec3 bitangent = normalize(cross(viewNormal, tangent) * at_tangent.w);
    tbn = mat3(tangent, bitangent, viewNormal);

    // Dirección de vista (fragmento -> cámara) en espacio tangente.
    viewDirTS = normalize(-viewPos) * tbn;

    // --- Tile del atlas para acotar el POM ---
    vec2 midCoord = (gl_TextureMatrix[0] * mc_midTexCoord).xy;
    vec2 d        = texcoord - midCoord;
    tileBase = midCoord - abs(d);
    tileSize = abs(d) * 2.0;

    gl_Position = gl_ProjectionMatrix * vs;
}
