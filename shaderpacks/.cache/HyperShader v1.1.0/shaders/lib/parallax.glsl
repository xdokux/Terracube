#ifndef PARALLAX_GLSL
#define PARALLAX_GLSL

#include "/lib/common.glsl"

/* =====================================================================
   parallax.glsl  —  Parallax Occlusion Mapping (PILAR 4).
   Da profundidad 3D real a las texturas (adoquín, troncos…) marchando
   por el mapa de altura en espacio tangente.

   La altura se lee de normals.a (formato LabPBR: el canal alfa del mapa
   de normales guarda el heightmap; 1.0 = superficie, valores menores =
   hundido). Si tu resource pack la guarda invertida, quita el "1.0 -".

   ATLAS: las texturas de bloques viven en un atlas. Marchamos en espacio
   LOCAL del tile [0..1] y envolvemos con fract() para no invadir tiles
   vecinos. tileBase/tileSize se calculan en el .vsh con mc_midTexCoord.
   ===================================================================== */

vec2 parallaxOcclusion(vec2 uv, vec3 viewTS, vec2 tileBase, vec2 tileSize,
                       sampler2D normalsTex) {
#if POM_LAYERS <= 0
    return uv;                                  // POM desactivado
#else
    float layers     = float(POM_LAYERS);
    float layerDepth = 1.0 / layers;

    // Vector de parallax: dirección de vista proyectada, escalada por la
    // profundidad deseada. max(abs(z)) evita divisiones explosivas en bordes.
    vec2 P      = (viewTS.xy / max(abs(viewTS.z), 0.05)) * POM_DEPTH;
    vec2 dLocal = (P / tileSize) / layers;       // paso en espacio local del tile

    vec2 local  = (uv - tileBase) / tileSize;    // coord local inicial [0..1]
    float curDepth = 0.0;
    float h = 1.0 - texture2D(normalsTex, tileBase + fract(local) * tileSize).a;

    // Raymarch lineal: avanzamos hasta que la profundidad supere la altura.
    for (int i = 0; i < POM_LAYERS; i++) {
        if (curDepth >= h) break;
        local    -= dLocal;
        curDepth += layerDepth;
        h = 1.0 - texture2D(normalsTex, tileBase + fract(local) * tileSize).a;
    }

    // Refinamiento (1 paso de interpolación) para suavizar el escalonado.
    vec2  prev   = local + dLocal;
    float hPrev  = 1.0 - texture2D(normalsTex, tileBase + fract(prev) * tileSize).a;
    float after  = h - curDepth;
    float before = hPrev - (curDepth - layerDepth);
    float w = after / (after - before);
    local = mix(local, prev, clamp(w, 0.0, 1.0));

    return tileBase + fract(local) * tileSize;
#endif
}

#endif
