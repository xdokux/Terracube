#ifndef CLOUDS_GLSL
#define CLOUDS_GLSL

#include "/lib/common.glsl"
#include "/lib/noise.glsl"

/* =====================================================================
   clouds.glsl  —  Capa de nubes COMPARTIDA (v1.1).
   La usan el cielo (deferred.fsh) y las sombras de nubes del terreno
   (gbuffers_terrain.fsh). Al compartir el mismo ruido, la sombra que
   pasa por el suelo coincide con la nube que ves arriba.
   ===================================================================== */

// Capa 1 (la dominante, 4 octavas). planeXZ en coords de MUNDO.
float cloudLayer1(vec2 planeXZ, float t) {
    return fbm(planeXZ * 0.0006 + t * (0.004 * CLOUD_SPEED), 4);
}

// Ruido -> cobertura [0..1]. La lluvia sube la cobertura => cielo
// encapotado y sombras de nube coherentes durante la tormenta.
float cloudCoverage(float n, float rain) {
    float cov = CLOUD_COVERAGE + rain * 0.30;
    return smoothstep(1.0 - cov, 1.0 - cov + 0.30, n);
}

/* Factor de luz solar [0..1] que llega al suelo bajo las nubes.
   Proyecta el fragmento hacia la capa de nubes (~140 m) siguiendo al sol. */
float cloudShadow(vec3 worldPos, vec3 sunDirW, float t, float rain) {
#if CLOUD_SHADOWS == 1
    float sy = max(sunDirW.y, 0.30);                   // evita estirones al atardecer
    vec2  cp = worldPos.xz + sunDirW.xz / sy * 140.0;
    float cov = cloudCoverage(cloudLayer1(cp, t), rain);
    return 1.0 - cov * CLOUD_SHADOW_STRENGTH;
#else
    return 1.0;
#endif
}

#endif
