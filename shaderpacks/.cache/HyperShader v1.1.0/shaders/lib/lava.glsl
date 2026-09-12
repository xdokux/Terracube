#ifndef LAVA_GLSL
#define LAVA_GLSL

#include "/lib/common.glsl"
#include "/lib/noise.glsl"

/* =====================================================================
   lava.glsl  —  Lava fluida e incandescente (PILAR 2).
   Se usa en gbuffers_terrain.fsh.

   Tres ingredientes:
   1) FLUJO VISCOSO: desplazamos las UV con un campo de ruido que avanza
      LENTO (LAVA_FLOW_SPEED bajo) => sensación de fluido pesado/denso.
   2) MAPA DE TEMPERATURA: un fbm decide qué zonas están al rojo vivo
      (blanco/amarillo) y cuáles son costra de roca enfriada (rojo oscuro).
   3) EMISIÓN HDR: devolvemos color por encima de 1.0 para que el tone
      mapping + el lightmap cálido tiñan el entorno de naranja.
   ===================================================================== */

// Rampa de color por temperatura [0 = costra fría .. 1 = incandescente].
// Los valores >1 son HDR a propósito (sobreexponen y se ven "al rojo blanco").
vec3 lavaTemperatureRamp(float t) {
    vec3 crust  = vec3(0.06, 0.012, 0.006); // roca enfriada, casi negra
    vec3 red    = vec3(1.00, 0.060, 0.015); // rojo intenso y puro
    vec3 orange = vec3(1.55, 0.260, 0.030); // naranja rojizo (poco verde)
    vec3 yellow = vec3(1.90, 0.700, 0.100); // ámbar, no amarillo chillón
    vec3 white  = vec3(2.60, 1.400, 0.500); // núcleo cálido (no blanco puro)

    // Umbrales desplazados: el rojo/naranja dominan; el ámbar/blanco solo
    // aparecen en lo más caliente => lava globalmente más ROJA.
    vec3 c = mix(crust,  red,    smoothstep(0.08, 0.35, t));
    c      = mix(c,      orange, smoothstep(0.40, 0.65, t));
    c      = mix(c,      yellow, smoothstep(0.72, 0.88, t));
    c      = mix(c,      white,  smoothstep(0.92, 1.00, t));
    return c;
}

/* Color emisivo de la lava.
   - uv : coordenada espacial. Pásale worldPos.xz (en bloques) para que el
          patrón sea continuo entre bloques contiguos.
   - t  : frameTimeCounter.
   - emissive (out): factor de emisión [≈0 costra .. LAVA_EMISSION_STRENGTH]. */
vec3 lavaEmission(vec2 uv, float t, out float emissive) {
    vec2 p = uv * LAVA_NOISE_SCALE;

    // 1) Campo de flujo: dos capas de ruido que avanzan en direcciones
    //    distintas y LENTO => advección orgánica y viscosa.
    float ft = t * LAVA_FLOW_SPEED;
    vec2 flow = vec2(
        fbm(p + vec2( ft * 0.6,  ft * 0.2), 3),
        fbm(p + vec2(-ft * 0.3,  ft * 0.5), 3)
    );
    // Deformamos las UV con el campo de flujo (advección barata, 1 nivel).
    vec2 warped = p + (flow - 0.5) * 0.8;

    // 2) Temperatura: fbm sobre las UV ya deformadas + un pulso de "respiración".
    float temp = fbm(warped + ft * 0.15, 4);
    temp += 0.08 * sin(t * 0.5 + warped.x * 1.3);
    temp  = clamp(temp * 1.3 - 0.15, 0.0, 1.0);

    // 3) Costra: las zonas frías forman vetas oscuras de roca solidificada.
    //    Realzamos el contraste para separar magma brillante de costra.
    float crustMask = smoothstep(0.30, 0.05, temp); // 1 donde está frío
    temp = mix(temp, temp * 0.4, crustMask);

    vec3 color = lavaTemperatureRamp(temp);

    // La emisión escala con la temperatura: la costra apenas brilla; el
    // magma blanco satura el HDR y alimenta el bloom/tone mapping.
    emissive = mix(0.15, 1.0, smoothstep(0.25, 0.90, temp)) * LAVA_EMISSION_STRENGTH;
    return color * emissive;
}

/* Lava tipo Solas: parte de la TEXTURA vanilla de lava (animada, con su detalle
   molten) y le da un grado cálido (naranja-rojo, menos amarillo neón), costra
   roja en lo oscuro, núcleo blanco en lo más caliente, y la lleva a HDR para
   que brille con el bloom. */
vec3 lavaFromTexture(vec3 texColor) {
    float t = clamp(dot(texColor, vec3(0.33)) * 1.25, 0.0, 1.0);
    vec3 c = texColor * vec3(1.55, 0.36, 0.08);                         // naranja-rojo (verde muy bajo)
    c = mix(c * vec3(1.25, 0.12, 0.03), c, smoothstep(0.18, 0.55, t));  // costra ROJA marcada y amplia
    c += vec3(0.45, 0.15, 0.03) * smoothstep(0.82, 1.0, t);            // núcleo naranja claro
    return c * (LAVA_EMISSION_STRENGTH * 0.55);                         // intensidad para que brille con bloom
}

#endif
