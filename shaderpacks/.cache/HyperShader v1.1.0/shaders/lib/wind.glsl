#ifndef WIND_GLSL
#define WIND_GLSL

#include "/lib/common.glsl"

/* =====================================================================
   wind.glsl  —  Desplazamiento de viento para la vegetación.
   Combinamos senos en distintas frecuencias para un balanceo orgánico
   (no robótico). 'topMask' pondera el movimiento: 0 = base fija (raíz),
   1 = punta (se mueve del todo). Para hojas usa 1.0 (bloque entero).
   ===================================================================== */

vec3 windDisplacement(vec3 worldPos, float t, float topMask, float strength) {
    float a = t * (1.6 * WAVE_SPEED);

    vec3 w;
    // Balanceo principal en X/Z, desfasado por la posición => cada planta
    // se mueve distinto a su vecina.
    w.x = sin(a + worldPos.x * 0.7 + worldPos.z * 0.4);
    w.z = cos(a * 0.9 + worldPos.z * 0.7 + worldPos.x * 0.3);
    // Ráfaga lenta y amplia que recorre el terreno.
    w.x += 0.4 * sin(a * 0.35 + worldPos.x * 0.12);
    w.z += 0.4 * cos(a * 0.30 + worldPos.z * 0.12);
    // Pequeño cabeceo vertical para que no parezca un deslizamiento plano.
    w.y = -0.12 * (abs(w.x) + abs(w.z));

    return w * (strength * WAVE_STRENGTH * topMask);
}

#endif
