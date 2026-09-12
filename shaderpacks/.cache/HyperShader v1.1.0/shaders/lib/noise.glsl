#ifndef NOISE_GLSL
#define NOISE_GLSL

/* =====================================================================
   noise.glsl  —  Ruido procedural barato (sin texturas).
   Optimizado para iGPU: hashing por seno + interpolación quintic.
   Usamos pocas octavas (3-4) porque cada octava es una llamada extra
   a valueNoise; en la 610M eso importa.
   ===================================================================== */

// Hash determinista 2D -> 1D. Barato, sin dependencias de textura.
float hash12(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Ruido de valor 2D con interpolación quintic (curva de Perlin: 6t^5-15t^4+10t^3).
float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = hash12(i + vec2(0.0, 0.0));
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractional Brownian Motion: suma de octavas. Rotamos el plano entre
// octavas para romper la alineación de la cuadrícula y evitar artefactos.
float fbm(vec2 p, int octaves) {
    float sum  = 0.0;
    float amp  = 0.5;
    float freq = 1.0;
    mat2  rot  = mat2(0.80, 0.60, -0.60, 0.80);
    for (int i = 0; i < octaves; i++) {
        sum  += amp * valueNoise(p * freq);
        p     = rot * p;
        freq *= 2.0;
        amp  *= 0.5;
    }
    return sum;
}

#endif
