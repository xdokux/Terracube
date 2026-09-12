#ifndef GERSTNER_GLSL
#define GERSTNER_GLSL

#include "/lib/common.glsl"

/* =====================================================================
   gerstner.glsl  —  Olas de Gerstner para la superficie del agua.
   (PILAR 1 — se usa en el Vertex Shader: gbuffers_water.vsh)

   Una ola de Gerstner no solo sube/baja el vértice (como una senoidal):
   además lo ARRASTRA horizontalmente hacia las crestas. Eso produce
   crestas afiladas y valles anchos => movimiento orgánico del oleaje,
   no el típico "ondular plano".

   Sumamos 4 olas con distinta dirección/longitud/velocidad para romper
   la repetición. Coste fijo y bajo (ideal para la 610M).
   Referencia: GPU Gems 1, cap. 1 (Finch).
   ===================================================================== */

struct GerstnerWave {
    vec2  dir;        // dirección de avance en el plano XZ (se normaliza dentro)
    float amplitude;  // A: altura de la ola
    float wavelength; // L: longitud de onda  ->  w = 2*PI / L
    float speed;      // velocidad de fase
    float steepness;  // Q en [0,1]: 0 = senoidal suave; ~0.9 = cresta afilada
};

/* Acumula UNA ola de Gerstner sobre el desplazamiento y la normal.
   - worldPosXZ : posición horizontal del vértice en espacio MUNDO
                  (en mundo para que las olas no dependan de dónde mire el jugador).
   - t          : tiempo (frameTimeCounter).
   - offset     : (inout) desplazamiento XYZ acumulado a aplicar al vértice.
   - normal     : (inout) normal analítica acumulada (se normaliza al final). */
void accumulateGerstner(GerstnerWave wv, vec2 worldPosXZ, float t,
                        inout vec3 offset, inout vec3 normal) {
    vec2  D   = normalize(wv.dir);
    float w   = TAU / wv.wavelength;     // frecuencia angular
    float phi = wv.speed * w;            // fase (dispersión simple)
    float Q   = wv.steepness;            // [0,1]; amplitud baja => sin auto-intersección
    float A   = wv.amplitude;

    float phase = w * dot(D, worldPosXZ) + phi * t;
    float s = sin(phase);
    float c = cos(phase);

    // --- Desplazamiento del vértice (Y es "arriba" en Minecraft) ---
    offset.x += Q * A * D.x * c;   // arrastre horizontal hacia la cresta
    offset.z += Q * A * D.y * c;
    offset.y += A * s;             // subida / bajada vertical

    // --- Normal analítica (derivada de la posición; gratis vs. derivadas en fsh) ---
    float WA = w * A;
    normal.x -= D.x * WA * c;
    normal.z -= D.y * WA * c;
    normal.y -= Q * WA * s;        // se resta de la normal.y inicial (=1.0)
}

/* Oleaje completo. Devuelve el desplazamiento del vértice y escribe la
   normal de la superficie en 'outNormal'.
   4 olas: 2 grandes (mar de fondo / swell) + 2 pequeñas (ondas de viento). */
vec3 gerstnerSurface(vec2 worldPosXZ, float t, out vec3 outNormal) {
    float H = WATER_WAVE_HEIGHT;   // escala global de amplitud (opción del usuario)
    float V = WATER_WAVE_SPEED;    // escala global de velocidad

    //                          dir            amp      L     speed     Q
    GerstnerWave w0 = GerstnerWave(vec2( 1.0,  0.6), H*1.00, 9.0, 1.10*V, 0.85);
    GerstnerWave w1 = GerstnerWave(vec2(-0.7,  1.0), H*0.70, 6.0, 1.35*V, 0.80);
    GerstnerWave w2 = GerstnerWave(vec2( 0.4, -1.0), H*0.40, 3.2, 1.80*V, 0.70);
    GerstnerWave w3 = GerstnerWave(vec2(-1.0, -0.3), H*0.25, 1.7, 2.40*V, 0.60);

    vec3 offset = vec3(0.0);
    vec3 normal = vec3(0.0, 1.0, 0.0);   // partimos de Y para construir 1 - Σ(...)

    accumulateGerstner(w0, worldPosXZ, t, offset, normal);
    accumulateGerstner(w1, worldPosXZ, t, offset, normal);
    accumulateGerstner(w2, worldPosXZ, t, offset, normal);
    accumulateGerstner(w3, worldPosXZ, t, offset, normal);

    outNormal = normalize(normal);
    return offset;
}

#endif
