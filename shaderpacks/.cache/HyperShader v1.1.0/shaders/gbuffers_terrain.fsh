#version 120

/* gbuffers_terrain.fsh
   - PILAR 4: POM + normal mapping.
   - PILAR 2: lava incandescente + tinte cálido de la luz de bloque.
   - PILAR 3: sombras suaves (PCSS).
   - Iluminación con ciclo día/noche: noches más oscuras y azuladas.
   - v1.1: mojado/charcos al llover, sombras de nubes, luz en mano,
     destello de relámpagos. */

#include "/lib/common.glsl"
#include "/lib/lava.glsl"
#include "/lib/shadows.glsl"
#include "/lib/parallax.glsl"
#include "/lib/noise.glsl"
#include "/lib/clouds.glsl"

uniform sampler2D gtexture;       // albedo del atlas
uniform sampler2D normals;        // LabPBR: rg = normal.xy, a = height
uniform sampler2D lightmap;

uniform sampler2D shadowtex0;
uniform mat4  gbufferModelViewInverse;
uniform mat4  shadowModelView;
uniform mat4  shadowProjection;
uniform vec3  shadowLightPosition;
uniform vec3  sunPosition;
uniform float frameTimeCounter;
uniform float rainStrength;       // lluvia AHORA (sube/baja rápido)
uniform float wetness;            // lluvia suavizada (moja y seca despacio)
uniform int   heldBlockLightValue;    // luz del bloque en mano principal
uniform int   heldBlockLightValue2;   // ... y en la otra mano
uniform vec4  lightningBoltPosition;  // Iris: w = 1 mientras hay rayo

varying vec2  texcoord;
varying vec2  lmcoord;
varying vec4  vColor;
varying vec3  viewPos;
varying vec3  worldPos;
varying vec3  viewNormal;
varying mat3  tbn;
varying vec3  viewDirTS;
varying vec2  tileBase;
varying vec2  tileSize;
varying float matID;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(41.0, 289.0))) * 43758.5453); }

/* DRAWBUFFERS:01 */
void main() {
    vec2 uv = texcoord;
#if POM_LAYERS > 0
    if (matID != 0.25 && matID != 0.15)   // sin POM en lava ni en follaje (evita líneas raras)
        uv = parallaxOcclusion(texcoord, normalize(viewDirTS), tileBase, tileSize, normals);
#endif

    vec4 albedo = texture2D(gtexture, uv) * vColor;
    if (albedo.a < 0.1) discard;

    float emissive = 0.0;
    vec3  fragNormal = viewNormal;

    if (matID == 0.25) {
        albedo.rgb = lavaFromTexture(albedo.rgb);   // lava tipo Solas (textura + grado cálido + HDR)
    } else if (matID != 0.15) {            // el follaje NO usa normal map (queda plano, sin artefactos)
        vec3 nTS = texture2D(normals, uv).xyz * 2.0 - 1.0;
        nTS.z = sqrt(clamp(1.0 - dot(nTS.xy, nTS.xy), 0.0, 1.0));
        fragNormal = normalize(tbn * nTS);
    }

    // --- Día/noche según la altura del sol en el mundo ---
    vec3  sunWorld  = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float dayFactor = smoothstep(-0.08, 0.20, sunWorld.y);   // 0 noche -> 1 día

    // --- CLIMA v1.1: superficies mojadas y charcos (solo a cielo abierto) ---
    float wetMask = 0.0;
    float puddle  = 0.0;
#if WET_EFFECTS == 1
    wetMask = wetness * smoothstep(0.80, 0.95, lmcoord.y);   // la lluvia no moja interiores
    if (wetMask > 0.01 && matID != 0.25) {
        // mojado: más oscuro y más saturado
        albedo.rgb = pow(albedo.rgb, vec3(1.0 + 0.30 * wetMask)) * (1.0 - 0.10 * wetMask);
#if PUDDLES == 1
        float upMask = smoothstep(0.75, 0.95, (mat3(gbufferModelViewInverse) * fragNormal).y);
        if (upMask > 0.0 && matID != 0.15) {
            float pn   = fbm(worldPos.xz * 0.28, 2);
            float edge = 0.78 - 0.28 * PUDDLE_AMOUNT * wetMask;   // más mojado => más charco
            puddle = smoothstep(edge, edge + 0.08, pn) * upMask * wetMask;
            // el charco es un espejo plano: normal hacia ARRIBA (en espacio de vista)
            vec3 upView = normalize(transpose(mat3(gbufferModelViewInverse)) * vec3(0.0, 1.0, 0.0));
            fragNormal = normalize(mix(fragNormal, upView, puddle * 0.9));
            albedo.rgb *= 1.0 - 0.25 * puddle;                    // el agua oscurece el suelo
        }
#endif
    }
#endif

    // Luz de bloque cálida (antorchas/lava tiñen el entorno).
    float blockLight = lmcoord.x;
    vec3  blockLighting = vec3(1.0, 0.55, 0.22) * pow(blockLight, 2.2) * 2.0;

    // v1.1: luz dinámica de la antorcha/lámpara EN LA MANO.
#if HANDLIGHT == 1
    float held = max(float(heldBlockLightValue), float(heldBlockLightValue2));
    if (held > 0.5) {
        float att = clamp(1.0 - length(viewPos) / (held * 0.85), 0.0, 1.0);
        blockLighting += vec3(1.00, 0.58, 0.24) * (att * att) * (held / 15.0) * 1.6 * HANDLIGHT_STRENGTH;
    }
#endif

    // Luz direccional: sol (día) o luna (noche).
    vec3  L = normalize(shadowLightPosition);
    float NdotL = max(dot(fragNormal, L), 0.0);

    // Sombra del sol. La calculamos también para caras que NO miran al sol
    // cuando INTERIOR_DARKEN está activo, porque la usamos para oscurecer el
    // ambiente en interiores: que la luz del día no "entre" en espacios
    // cerrados aunque el lightmap esté forzado (p.ej. Fullbright del cliente).
    float shade = 1.0;
    if (matID != 0.25 && (NdotL > 0.0 || INTERIOR_DARKEN < 0.99)) {
        float dither = hash21(gl_FragCoord.xy);
        // v1.1.1: normal-offset — muestreamos la sombra un poco POR ENCIMA de
        // la superficie (siguiendo su normal geométrica) para que el bloque no
        // se dé sombra a sí mismo => adiós líneas diagonales (shadow acne).
        vec3  sPos   = worldToShadow(viewPos + viewNormal * 0.06, gbufferModelViewInverse, shadowModelView, shadowProjection);
        float texel  = 1.0 / float(shadowMapResolution);
        shade = softShadow(shadowtex0, sPos, texel, dither);
    }

    // Ambiente del cielo, ATENUADO donde el sol no llega (interiores/sombra).
    float skyLight = lmcoord.y;
    vec3  ambient  = SKY_COLOR * (0.035 + skyLight * mix(0.07 * NIGHT_BRIGHTNESS, 0.45, dayFactor));
    ambient *= mix(INTERIOR_DARKEN, 1.0, shade);   // <- clave: interiores más oscuros
    ambient *= 1.0 - 0.20 * rainStrength;          // v1.1: día encapotado = ambiente más plano

    // v1.1: el relámpago ilumina el terreno un instante (azulado).
#if LIGHTNING_FLASH == 1
    ambient += vec3(0.55, 0.62, 0.90) * lightningBoltPosition.w * 0.9 * skyLight;
#endif

    // Atardecer/amanecer => la luz directa del sol se vuelve naranja.
    float sunset = smoothstep(0.35, 0.0, sunWorld.y) * smoothstep(-0.18, 0.10, sunWorld.y);
    vec3  lightColor    = mix(MOON_COLOR, SUN_COLOR, dayFactor);
    lightColor = mix(lightColor, vec3(1.0, 0.42, 0.14), sunset * 0.95);
    float lightStrength = mix(0.10 * NIGHT_BRIGHTNESS, SUN_BRIGHTNESS, dayFactor);

    // v1.1: sombras de nubes en movimiento + menos sol directo bajo la lluvia.
    float cShade = cloudShadow(worldPos, sunWorld, frameTimeCounter, rainStrength) * dayFactor
                 + (1.0 - dayFactor);              // de noche no se aplica
    vec3  direct = lightColor * NdotL * shade * lightStrength * cShade;
    direct *= 1.0 - 0.55 * rainStrength;

    // v1.1: brillo del suelo mojado + reflejo del cielo en los charcos.
    vec3 wetSpec = vec3(0.0);
#if WET_EFFECTS == 1
    if (wetMask > 0.01 && matID != 0.25) {
        vec3  V = normalize(-viewPos);
        vec3  H = normalize(L + V);
        float fres  = pow(1.0 - max(dot(fragNormal, V), 0.0), 5.0);
        float glint = pow(max(dot(fragNormal, H), 0.0), mix(28.0, 160.0, puddle));
        // gotas cayendo: chispas que parpadean en los charcos
        float sparkle = 0.75 + 0.50 * valueNoise(worldPos.xz * 4.0 - frameTimeCounter * 2.2);
        wetSpec  = lightColor * glint * shade * cShade * lightStrength
                 * (0.10 * wetMask + 0.85 * puddle * sparkle);
        wetSpec += SKY_COLOR * fres * puddle * skyLight * mix(0.05, 0.30, dayFactor);
    }
#endif

    vec3 lit = (matID == 0.25)
             ? albedo.rgb                                   // lava: 100% emisiva
             : albedo.rgb * (ambient + blockLighting + direct) + wetSpec;

    gl_FragData[0] = vec4(lit, albedo.a);
    gl_FragData[1] = vec4(fragNormal * 0.5 + 0.5, matID);
}
