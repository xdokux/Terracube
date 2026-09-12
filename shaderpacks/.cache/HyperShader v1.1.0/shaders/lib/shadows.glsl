#ifndef SHADOWS_GLSL
#define SHADOWS_GLSL

#include "/lib/common.glsl"

/* =====================================================================
   shadows.glsl  —  Sombras suaves con contacto endurecido (PILAR 3).
   Usa una versión ligera de PCSS:
     1) Búsqueda de bloqueadores (pocas muestras) -> profundidad media
        de lo que tapa el sol.
     2) Penumbra proporcional a la distancia receptor<->bloqueador
        => sombra nítida pegada al objeto y difusa lejos de él.
     3) PCF con radio adaptativo (espiral de ángulo áureo, sin arrays
        para mantener compatibilidad con #version 120).

   REQUISITO: el programa que lo incluya debe declarar:
     uniform sampler2D shadowtex0;
   (v1.1: shadowMapResolution ya es const en lib/common.glsl, no hace falta
    declararlo como uniform.)
   ===================================================================== */

#define SHADOW_DISTORT 0.90   // acerca resolución del shadow map al jugador

// Distorsión del shadow map: más detalle cerca de la cámara. DEBE aplicarse
// igual en shadow.vsh (al renderizar) y aquí (al muestrear).
vec2 distortShadow(vec2 p) {
    float d = length(p);
    float f = d * SHADOW_DISTORT + (1.0 - SHADOW_DISTORT);
    return p / f;
}

// Posición en espacio de VISTA -> coordenada del shadow map [0..1].
vec3 worldToShadow(vec3 viewPos, mat4 mvInv, mat4 sMV, mat4 sProj) {
    vec3 playerPos = (mvInv * vec4(viewPos, 1.0)).xyz;   // relativo a la cámara
    vec4 sClip = sProj * (sMV * vec4(playerPos, 1.0));
    sClip.xyz /= sClip.w;
    sClip.xy = distortShadow(sClip.xy);
    return sClip.xyz * 0.5 + 0.5;
}

// PCF en espiral. 'radiusTexels' = radio de penumbra en téxeles; 'dither'
// rota la espiral por píxel para romper el banding.
float pcfShadow(sampler2D sDepth, vec3 sPos, float radiusTexels, float texelSize, float dither) {
    float sum  = 0.0;
    float bias = 0.0012;
    const float GA = 2.39996323;             // ángulo áureo
    for (int i = 0; i < SHADOW_SAMPLES; i++) {
        float fi = float(i) + dither;
        float r  = sqrt((fi + 0.5) / float(SHADOW_SAMPLES));
        float a  = fi * GA;
        vec2 off = vec2(cos(a), sin(a)) * r * radiusTexels * texelSize;
        float d  = texture2D(sDepth, sPos.xy + off).r;
        sum += step(sPos.z - bias, d);        // 1 si el punto está iluminado
    }
    return sum / float(SHADOW_SAMPLES);
}

// PCSS ligero: busca bloqueadores y adapta el radio de la penumbra.
float softShadow(sampler2D sDepth, vec3 sPos, float texelSize, float dither) {
    float bias = 0.0012;

    // 1) Búsqueda de bloqueadores (4 muestras: barato para la 610M).
    float blockerSum = 0.0;
    float blockerCnt = 0.0;
    float searchR = 2.5 * texelSize * SHADOW_SOFTNESS;
    const float GA = 2.39996323;
    for (int i = 0; i < 4; i++) {
        float fi = float(i) + dither;
        float r  = sqrt((fi + 0.5) / 4.0);
        float a  = fi * GA;
        vec2 off = vec2(cos(a), sin(a)) * r * searchR;
        float d  = texture2D(sDepth, sPos.xy + off).r;
        if (d < sPos.z - bias) { blockerSum += d; blockerCnt += 1.0; }
    }
    if (blockerCnt < 0.5) return 1.0;          // nada tapa el sol => iluminado

    // 2) Penumbra proporcional a la separación receptor-bloqueador.
    float avgBlocker = blockerSum / blockerCnt;
    float penumbra   = (sPos.z - avgBlocker) / max(avgBlocker, 1e-4);
    float radiusTexels = clamp(penumbra * 60.0 * SHADOW_SOFTNESS, 0.6, 8.0);

    // 3) PCF con radio adaptativo.
    return pcfShadow(sDepth, sPos, radiusTexels, texelSize, dither);
}

#endif
