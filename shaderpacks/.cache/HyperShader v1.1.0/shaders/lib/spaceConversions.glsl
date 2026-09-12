#ifndef SPACE_CONVERSIONS_GLSL
#define SPACE_CONVERSIONS_GLSL

/* =====================================================================
   spaceConversions.glsl  —  Conversiones de espacio para SSR y sombras.

   Declaramos AQUÍ los uniforms que usan estas funciones (no en cada programa)
   para que existan al incluir este archivo arriba del todo: en GLSL hay que
   declarar antes de usar. El include-guard evita declararlos dos veces.
   IMPORTANTE: NO vuelvas a declarar estos uniforms en el programa que incluya
   este archivo, o dará error de declaración duplicada.
   ===================================================================== */

uniform mat4  gbufferProjection;
uniform mat4  gbufferProjectionInverse;
uniform float near;
uniform float far;

// Profundidad no lineal del depth buffer -> distancia lineal a la cámara.
// Útil para el grosor del agua y para comparar profundidades en SSR.
float linearizeDepth(float depth) {
    return (2.0 * near * far) / (far + near - (depth * 2.0 - 1.0) * (far - near));
}

// Coord de pantalla [0..1] + depth del buffer -> posición en espacio de VISTA.
vec3 screenToView(vec2 texcoord, float depth) {
    vec3 ndc  = vec3(texcoord, depth) * 2.0 - 1.0;
    vec4 view = gbufferProjectionInverse * vec4(ndc, 1.0);
    return view.xyz / view.w;
}

// Posición en espacio de VISTA -> coord de pantalla [0..1] (xy) + depth (z).
// (Para muestrear buffers durante el raymarch de SSR / god rays.)
vec3 viewToScreen(vec3 viewPos) {
    vec4 clip = gbufferProjection * vec4(viewPos, 1.0);
    vec3 ndc  = clip.xyz / clip.w;
    return ndc * 0.5 + 0.5;
}

#endif
