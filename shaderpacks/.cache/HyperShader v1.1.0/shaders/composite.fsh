#version 120

/* composite.fsh — Pases diferidos a pantalla completa.
   - PILAR 1: SSR sobre el agua (con reflejo del cielo real al no encontrar nada).
   - PILAR 3: God Rays (solo de día).
   - NIEBLA atmosférica de distancia (solo en el borde lejano) + niebla submarina.
   - v1.1: refracción del agua, cáusticas, arcoíris tras la lluvia,
     SSR con refinamiento binario + desvanecido en bordes.

   El CIELO se dibuja en deferred.fsh (antes del clima), no aquí, para que la
   nieve/lluvia se vea también contra el cielo. */

#include "/lib/common.glsl"
#include "/lib/spaceConversions.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/noise.glsl"

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16;
const int colortex2Format = RGBA16F;
const int colortex3Format = RGBA16F;
*/

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;    // profundidad SOLO de opacos (fondo del agua)

uniform mat4  gbufferModelViewInverse;
uniform vec3  sunPosition;
uniform vec3  cameraPosition;
uniform float viewWidth, viewHeight;
uniform float frameTimeCounter;
uniform float wetness;          // rainStrength llega desde atmosphere.glsl
uniform int   isEyeInWater;

varying vec2 texcoord;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(41.0, 289.0))) * 43758.5453); }

// v1.1: patrón de CÁUSTICAS — dos ruidos que se cruzan en direcciones
// opuestas; al multiplicarse forman filamentos brillantes que bailan.
float causticPattern(vec2 p, float t) {
    float a = valueNoise(p * 0.9 + vec2(t * 0.9,  t * 0.6));
    float b = valueNoise(p * 1.1 - vec2(t * 0.7,  t * 1.0) + 31.0);
    return pow(clamp(a * b * 2.2, 0.0, 1.0), 3.0);
}

// v1.1: color del arcoíris; h = 0 borde exterior (rojo) .. 1 interior (violeta).
vec3 rainbowColor(float h) {
    float k = h * 0.75;   // recorre el círculo de tono de rojo a violeta
    return clamp(vec3(abs(k * 6.0 - 3.0) - 1.0,
                      2.0 - abs(k * 6.0 - 2.0),
                      2.0 - abs(k * 6.0 - 4.0)), 0.0, 1.0);
}

// --- PILAR 1: SSR. Si no golpea nada, devuelve el cielo real reflejado.
//     v1.1: paso creciente (más alcance), refinamiento binario del impacto
//     (adiós "rayas") y fade en bordes de pantalla (adiós cortes bruscos). ---
vec3 screenSpaceReflection(vec3 viewPos, vec3 N, float dayFactor) {
    vec3 R = reflect(normalize(viewPos), N);
    vec3 skyFallback = atmosphere(normalize(mat3(gbufferModelViewInverse) * R), dayFactor);

    vec3 stepV = R * 0.5;
    vec3 rayVS = viewPos;
    vec3 prev  = rayVS;
    for (int i = 0; i < SSR_STEPS; i++) {
        prev   = rayVS;
        rayVS += stepV;
        vec3 uvz = viewToScreen(rayVS);
        if (uvz.x < 0.0 || uvz.x > 1.0 || uvz.y < 0.0 || uvz.y > 1.0) break;
        float sceneDepth = texture2D(depthtex0, uvz.xy).r;
        if (sceneDepth < 1.0) {
            vec3  scenePos = screenToView(uvz.xy, sceneDepth);
            float diff = rayVS.z - scenePos.z;
            if (diff < 0.0 && diff > -2.5 * length(stepV)) {
                // refinamiento binario: 4 bisecciones afinan el impacto
                vec3 lo = prev, hi = rayVS;
                for (int j = 0; j < 4; j++) {
                    vec3 mid = (lo + hi) * 0.5;
                    vec3 muv = viewToScreen(mid);
                    float md = texture2D(depthtex0, muv.xy).r;
                    if (mid.z - screenToView(muv.xy, md).z < 0.0) hi = mid;
                    else                                          lo = mid;
                }
                vec3 fuv = viewToScreen((lo + hi) * 0.5);
                vec2 e   = min(fuv.xy, vec2(1.0) - fuv.xy);
                float fade = smoothstep(0.0, 0.08, min(e.x, e.y));
                return mix(skyFallback, texture2D(colortex0, fuv.xy).rgb, fade);
            }
        }
        stepV *= 1.30;   // paso creciente: mismo coste, más alcance
    }
    return skyFallback;
}

// --- PILAR 3: God Rays radiales hacia el sol ---
vec3 godRays(vec2 uv) {
    vec3 sunScreen = viewToScreen(sunPosition);
    if (sunScreen.z > 1.0) return vec3(0.0);
    vec2  stepv = (sunScreen.xy - uv) / float(GODRAY_SAMPLES) * 0.6;
    float illum = 1.0, accum = 0.0;
    vec2  p = uv + stepv * hash21(uv * vec2(viewWidth, viewHeight));
    for (int i = 0; i < GODRAY_SAMPLES; i++) {
        p += stepv;
        float d = texture2D(depthtex0, clamp(p, 0.0, 1.0)).r;
        accum += step(0.9999, d) * illum;
        illum *= 0.92;
    }
    accum /= float(GODRAY_SAMPLES);
    float falloff = max(0.0, 1.0 - length(sunScreen.xy - uv));
    return SUN_COLOR * accum * falloff * GODRAY_STRENGTH;
}

/* DRAWBUFFERS:0 */
void main() {
    float depth = texture2D(depthtex0, texcoord).r;
    vec4  mat   = texture2D(colortex1, texcoord);
    float matID = mat.a;
    vec3  N     = normalize(mat.rgb * 2.0 - 1.0);

    vec3 viewPos = screenToView(texcoord, depth);
    bool isSky   = depth >= 1.0;
    bool isWater = !isSky && matID > 0.45 && matID < 0.55;

    vec3  sunDirW   = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float dayFactor = smoothstep(-0.08, 0.20, sunDirW.y);

    // v1.1 REFRACCIÓN: en el agua, leemos el color un poco desplazado según
    // la normal de las olas => el fondo se deforma. Solo aceptamos el desvío
    // si detrás hay fondo de verdad (no un objeto por delante del agua).
    vec2 uvR = texcoord;
#if REFRACTION == 1
    if (isWater) {
        vec2 cand = texcoord + N.xy * (0.015 * REFRACTION_STRENGTH)
                    / max(1.0, length(viewPos) * 0.12);
        if (texture2D(depthtex1, cand).r > depth) uvR = cand;
    }
#endif
    vec3 color = texture2D(colortex0, uvR).rgb;

    // PILAR 1: SSR solo sobre agua.
    if (isWater) {
        vec3  refl = screenSpaceReflection(viewPos, N, dayFactor);
        vec3  Vv   = normalize(-viewPos);
        float fres = mix(0.02, 1.0, pow(1.0 - max(dot(N, Vv), 0.0), 5.0));
        color = mix(color, refl, fres * 0.8);
    }

    // v1.1 CÁUSTICAS vistas desde FUERA: filamentos de luz en el fondo,
    // atenuados con el grosor del agua.
#if CAUSTICS == 1
    if (isWater && dayFactor > 0.02) {
        float dBack = texture2D(depthtex1, uvR).r;
        vec3  backView  = screenToView(uvR, dBack);
        vec3  backWorld = (gbufferModelViewInverse * vec4(backView, 1.0)).xyz + cameraPosition;
        float thick = max(length(backView) - length(viewPos), 0.0);
        float caus  = causticPattern(backWorld.xz, frameTimeCounter);
        color += SUN_COLOR * caus * exp(-thick * 0.35) * dayFactor * 0.35 * CAUSTICS_STRENGTH;
    }
#endif

    if (isEyeInWater == 1) {
        // v1.1 CÁUSTICAS estando SUMERGIDO: la luz baila sobre todo el fondo.
#if CAUSTICS == 1
        if (!isSky && dayFactor > 0.02) {
            vec3 wpos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
            float caus = causticPattern(wpos.xz, frameTimeCounter);
            color *= 1.0 + caus * 1.6 * CAUSTICS_STRENGTH * dayFactor;
        }
#endif
        float dist = length(viewPos);
        float fog  = 1.0 - exp(-dist * UNDERWATER_DENSITY);
        color = mix(color, vec3(0.02, 0.10, 0.16), clamp(fog, 0.0, 0.92));
    } else {
        // Niebla SOLO en el borde lejano del render => todo lo cercano nítido.
        if (!isSky) {
            vec3  fragDir = normalize(mat3(gbufferModelViewInverse) * normalize(viewPos));
            float dist = length(viewPos);
            float fog = smoothstep(far * 0.70, far * 0.98, dist) * FOG_DENSITY;
            color = mix(color, atmosphere(fragDir, dayFactor), clamp(fog, 0.0, 0.95));
        }
        // God rays: de día, y casi apagados mientras llueve (cielo tapado).
        color += godRays(texcoord) * dayFactor * (1.0 - 0.85 * rainStrength);

        // v1.1 ARCOÍRIS al escampar: 'wetness' baja despacio cuando deja de
        // llover mientras 'rainStrength' cae rápido => aparece justo después
        // de la tormenta y se desvanece solo. Banda a ~42° del punto antisolar.
#if RAINBOW == 1
        float rbVis = wetness * (1.0 - rainStrength) * dayFactor * RAINBOW_STRENGTH;
        if (rbVis > 0.01) {
            vec3  dirW = normalize(mat3(gbufferModelViewInverse) * normalize(viewPos));
            float c    = dot(dirW, -sunDirW);
            float band = (c - 0.7373) / (0.7604 - 0.7373);   // 42.5° .. 40.5°
            if (band > 0.0 && band < 1.0 && dirW.y > 0.0) {
                float aBand = sin(band * PI);
                float bg    = isSky ? 1.0 : smoothstep(far * 0.35, far * 0.80, length(viewPos));
                float horiz = smoothstep(0.0, 0.20, dirW.y);
                color += rainbowColor(band) * aBand * bg * horiz * 0.22 * rbVis;
            }
        }
#endif
    }

    gl_FragData[0] = vec4(color, 1.0);
}
