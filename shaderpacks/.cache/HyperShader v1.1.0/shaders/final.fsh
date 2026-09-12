#version 120

/* final.fsh — Pase final: HDR -> LDR.
   Exposición + tone mapping (ACES) + gamma + color grade (saturación/contraste).
   EXPOSURE permite bajar el brillo global (útil en biomas de nieve cegadores).
   v1.1: FXAA (suaviza dientes de sierra por ~5 lecturas de textura). */

#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex3;   // bloom (resplandor)
uniform float viewWidth, viewHeight;

varying vec2 texcoord;

vec3 aces(vec3 x) {
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

#if FXAA == 1
// Luma perceptual sobre HDR comprimido (x/(1+x) imita el tonemap).
float fxaaLuma(vec3 c) {
    c = c / (1.0 + c);
    return dot(c, vec3(0.299, 0.587, 0.114));
}

/* FXAA clásico (versión compacta de Lottes): detecta el borde con las 4
   diagonales, estima su dirección y promedia a lo largo de ella. */
vec3 fxaa(vec2 uv, vec2 px) {
    vec3 cC  = texture2D(colortex0, uv).rgb;
    vec3 cNW = texture2D(colortex0, uv + px * vec2(-1.0, -1.0)).rgb;
    vec3 cNE = texture2D(colortex0, uv + px * vec2( 1.0, -1.0)).rgb;
    vec3 cSW = texture2D(colortex0, uv + px * vec2(-1.0,  1.0)).rgb;
    vec3 cSE = texture2D(colortex0, uv + px * vec2( 1.0,  1.0)).rgb;

    float lC  = fxaaLuma(cC);
    float lNW = fxaaLuma(cNW), lNE = fxaaLuma(cNE);
    float lSW = fxaaLuma(cSW), lSE = fxaaLuma(cSE);
    float lMin = min(lC, min(min(lNW, lNE), min(lSW, lSE)));
    float lMax = max(lC, max(max(lNW, lNE), max(lSW, lSE)));

    vec2 dir = vec2(-((lNW + lNE) - (lSW + lSE)), (lNW + lSW) - (lNE + lSE));
    float dirReduce = max((lNW + lNE + lSW + lSE) * 0.03125, 0.0078125);
    float rcpMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcpMin, vec2(-8.0), vec2(8.0)) * px;

    vec3 rgbA = 0.5 * (texture2D(colortex0, uv + dir * (1.0 / 3.0 - 0.5)).rgb
                     + texture2D(colortex0, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (texture2D(colortex0, uv + dir * -0.5).rgb
                                   + texture2D(colortex0, uv + dir *  0.5).rgb);
    float lB = fxaaLuma(rgbB);
    return (lB < lMin || lB > lMax) ? rgbA : rgbB;
}
#endif

void main() {
#if FXAA == 1
    vec3 col = fxaa(texcoord, 1.0 / vec2(viewWidth, viewHeight));
#else
    vec3 col = texture2D(colortex0, texcoord).rgb;
#endif

#if BLOOM == 1
    col += texture2D(colortex3, texcoord).rgb * BLOOM_STRENGTH;   // resplandor (lava/lámparas/sol)
#endif

    col *= EXPOSURE;                  // exposición global (baja en escenas muy blancas)
    col = aces(col);                  // HDR -> LDR (comprime los blancos)
    col = pow(col, vec3(1.0 / 2.2));  // gamma

    // --- Color grade ---
    float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(l), col, SATURATION);
    col = clamp((col - 0.5) * CONTRAST + 0.5, 0.0, 1.0);

    gl_FragColor = vec4(col, 1.0);
}
