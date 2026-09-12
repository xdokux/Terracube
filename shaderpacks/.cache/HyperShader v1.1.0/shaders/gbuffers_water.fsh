#version 120

/* gbuffers_water.fsh — PILAR 1 (fragmento).
   - AGUA: degradado de absorción por profundidad + Fresnel + specular. Más
     opaca/azul para que el fondo NO se vea blanco. matID 0.5 => SSR en composite.
   - HIELO: su textura real con tinte azul claro y más opaco (se distingue del agua).
   - OTROS translúcidos (cristal…): su textura tal cual (ya no se ven como agua). */

#include "/lib/common.glsl"
#include "/lib/spaceConversions.glsl"
#include "/lib/noise.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform sampler2D depthtex1;          // profundidad SOLO de opacos
uniform vec3  shadowLightPosition;
uniform vec3  sunPosition;
uniform mat4  gbufferModelViewInverse;
uniform float viewWidth, viewHeight;
uniform float frameTimeCounter;
uniform float rainStrength;

varying vec2  texcoord;
varying vec2  lmcoord;
varying vec4  vColor;
varying vec3  viewPos;
varying vec3  worldPosW;
varying vec3  waveNormal;
varying float matKind;

/* DRAWBUFFERS:01 */
void main() {
    vec3  outColor;
    float outAlpha;
    float outMatID;
    vec3  N = normalize(waveNormal);

    if (matKind < 0.5) {
        // -------------------- AGUA --------------------
        // v1.1: gotas de lluvia ondulando la superficie (ruido de alta
        // frecuencia que solo aparece mientras llueve).
#if RAIN_RIPPLES == 1
        if (rainStrength > 0.01) {
            float r1 = valueNoise(worldPosW.xz * 2.6 + frameTimeCounter * 3.0);
            float r2 = valueNoise(worldPosW.xz * 2.6 - frameTimeCounter * 2.6 + 17.3);
            vec3  rip = vec3(r1 - 0.5, 0.0, r2 - 0.5) * (0.55 * rainStrength);
            N = normalize(N + transpose(mat3(gbufferModelViewInverse)) * rip);
        }
#endif

        vec2  screenUV  = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
        float backDist  = linearizeDepth(texture2D(depthtex1, screenUV).r);
        float frontDist = linearizeDepth(gl_FragCoord.z);
        float thickness = max(backDist - frontDist, 0.0);

        vec3  shallow = vec3(0.04, 0.16, 0.23);    // teal apagado (no un cian chillón)
        vec3  deep    = vec3(0.008, 0.040, 0.090);
        float absorb  = 1.0 - exp(-thickness * WATER_FOG_DENSITY);
        vec3  waterColor = mix(shallow, deep, absorb);
        // De noche el agua se oscurece para que no destaque como un blob brillante.
        float dayF = smoothstep(-0.08, 0.20, normalize(mat3(gbufferModelViewInverse) * sunPosition).y);
        waterColor *= mix(0.30, 1.0, dayF);

        vec3  V = normalize(-viewPos);
        float fresnel = mix(0.02, 1.0, pow(1.0 - max(dot(N, V), 0.0), 5.0));
        vec3  color = mix(waterColor, SKY_COLOR * 0.30, fresnel);

        vec3  L = normalize(shadowLightPosition);
        vec3  H = normalize(L + V);
        float spec = pow(max(dot(N, H), 0.0), 200.0);
        color += SUN_COLOR * spec * SUN_BRIGHTNESS;

        outAlpha = clamp(0.62 + absorb * 0.33 + fresnel * 0.10, 0.50, 0.97);

        // v1.1: ESPUMA donde el agua toca la orilla (poca profundidad),
        // rota con ruido animado para que no sea una línea perfecta.
#if FOAM == 1
        float foamBand = 1.0 - smoothstep(0.02, 0.50, thickness);
        float fn   = valueNoise(worldPosW.xz * 3.5 + vec2(frameTimeCounter * 0.9, -frameTimeCounter * 0.6));
        float foam = foamBand * smoothstep(0.55 - 0.35 * foamBand, 0.75, fn);
        vec3  foamCol = vec3(0.92, 0.96, 1.00) * mix(0.25, 1.0, dayF);
        color = mix(color, foamCol, clamp(foam, 0.0, 0.85));
        outAlpha = max(outAlpha, foam * 0.95);
#endif

        outColor = color;
        outMatID = 0.5;
    } else {
        // ------------- HIELO / PORTAL / otros translúcidos -------------
        vec4 tex = texture2D(gtexture, texcoord) * vColor;
        if (tex.a < 0.05) discard;

        if (matKind > 2.5) {
            // PORTAL del Nether: SIEMPRE lila puro (no se quema a blanco dentro); el brillo
            // lo modula el patrón. Va a HDR para que el BLOOM esparza la luz lila por FUERA.
            float ptn = dot(tex.rgb, vec3(0.4, 0.2, 0.5));     // patrón animado del portal
            outColor = vec3(0.80, 0.08, 1.00) * (1.0 + ptn * 3.5) * 2.6;
            outAlpha = max(tex.a, 0.72);
        } else {
            vec3 lit = tex.rgb * texture2D(lightmap, lmcoord).rgb;   // iluminación vanilla
            if (matKind < 1.5) {
                lit = mix(lit, vec3(0.62, 0.78, 0.92), 0.30);       // HIELO: azul-blanco, más opaco
                outAlpha = max(tex.a, 0.88);
            } else {
                outAlpha = tex.a;                                   // cristal, etc.: vanilla
            }
            outColor = lit;
        }
        outMatID = 0.0;                                             // sin SSR de agua
    }

    gl_FragData[0] = vec4(outColor, outAlpha);
    gl_FragData[1] = vec4(N * 0.5 + 0.5, outMatID);
}
