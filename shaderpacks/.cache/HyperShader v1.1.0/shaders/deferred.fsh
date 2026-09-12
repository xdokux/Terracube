#version 120

/* deferred.fsh — Dibuja el CIELO procedural en los píxeles sin geometría:
   atmósfera + galaxia + estrellas + estrellas fugaces + luna/sol redondos
   (con fases) + nubes + atardecer naranja.

   Va en 'deferred' (se ejecuta ANTES del agua y del clima), por eso la
   nieve/lluvia se dibuja ENCIMA del cielo y se ve por todo el cielo, no solo
   donde hay tierra detrás. */

#include "/lib/common.glsl"
#include "/lib/spaceConversions.glsl"
#include "/lib/noise.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/clouds.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform mat4  gbufferModelViewInverse;
uniform vec3  sunPosition;
uniform vec3  moonPosition;
uniform vec3  cameraPosition;
uniform float frameTimeCounter;
uniform int   moonPhase;
uniform vec4  lightningBoltPosition;   // Iris: xyz = rayo, w = 1 si hay rayo

varying vec2 texcoord;

float starHash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 4.1414))) * 43758.5453); }
vec2  skyPlane(vec3 dir) { return dir.xz / (abs(dir.y) + 1.0); }

// Estrellas procedurales (dos rejillas multiplicadas => puntos nítidos).
float starField(vec3 dir) {
    vec2 pc = skyPlane(dir) + frameTimeCounter * 0.0008;
    vec2 g0 = floor(pc * 380.0 * STAR_AMOUNT) / (380.0 * STAR_AMOUNT);
    vec2 g1 = floor(pc * 760.0 * STAR_AMOUNT) / (760.0 * STAR_AMOUNT);
    float n = starHash(g0 + 8.0) * starHash(g1 + 14.0);
    float s = clamp(n - 0.825, 0.0, 1.0);
#if STAR_TWINKLE == 1
    // cada estrella titila con fase propia (hash de su celda)
    s *= 0.70 + 0.30 * sin(frameTimeCounter * 3.5 + starHash(g0 * 91.7) * 40.0);
#endif
    return clamp(s * s * s * 512.0, 0.0, 12.0);
}

// Galaxia / Vía Láctea: banda inclinada con polvo (fbm).
vec3 galaxyColor(vec3 dir) {
    vec3  gn = normalize(vec3(0.55, 0.5, 0.66));
    float band = pow(1.0 - clamp(abs(dot(dir, gn)) * 1.5, 0.0, 1.0), 2.5);
    vec2  pc = skyPlane(dir) * 2.5;
    float dust  = fbm(pc, 3);
    float dust2 = fbm(pc * 2.7 + 11.0, 2);
    float density = band * smoothstep(0.25, 0.85, dust) * (0.35 + 0.65 * dust2);
    return mix(vec3(0.10, 0.12, 0.22), vec3(0.50, 0.34, 0.55), dust) * density;
}

// Estrella fugaz ocasional.
vec3 shootingStar(vec3 dir, float t) {
    float idx = floor(t / 7.0), local = fract(t / 7.0);
    float seed = starHash(vec2(idx, 3.7));
    if (seed < 0.45 || local > 0.22) return vec3(0.0);
    vec3 a   = normalize(vec3(seed * 2.0 - 1.0, 0.55 + 0.35 * starHash(vec2(idx, 5.1)), starHash(vec2(idx, 9.2)) * 2.0 - 1.0));
    vec3 vel = normalize(vec3(starHash(vec2(idx, 2.3)) * 2.0 - 1.0, -0.3, starHash(vec2(idx, 6.4)) * 2.0 - 1.0));
    float prog = local / 0.22;
    vec3 head = normalize(a + vel * prog * 0.7);
    vec3 tail = normalize(a + vel * max(prog - 0.10, 0.0) * 0.7);
    vec3 ab = head - tail, ap = dir - tail;
    float h = clamp(dot(ap, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
    float d = length(dir - (tail + ab * h));
    return vec3(0.9, 0.95, 1.0) * smoothstep(0.012, 0.0, d) * h * smoothstep(1.0, 0.7, prog);
}

// Disco redondo y suave de un astro.
float celestialDisc(vec3 dir, vec3 bodyDir, float size) {
    return smoothstep(cos(size), cos(size * 0.80), dot(dir, bodyDir));
}

// Cielo completo a partir de la posición de vista del píxel.
vec3 renderSky(vec3 viewPos, float dayFactor) {
    vec3 dir   = normalize(mat3(gbufferModelViewInverse) * normalize(viewPos));
    vec3 sunD  = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    vec3 moonD = normalize(mat3(gbufferModelViewInverse) * moonPosition);
    float night = 1.0 - dayFactor;
    float up    = smoothstep(-0.05, 0.15, dir.y);
    float sunset = smoothstep(0.35, 0.0, sunD.y) * smoothstep(-0.18, 0.10, sunD.y);

    vec3 sky = atmosphere(dir, dayFactor);

    // Resplandor NARANJA en el horizonte hacia el sol (atardecer/amanecer).
    vec2  dh = normalize(vec2(dir.x,  dir.z)  + 1e-5);
    vec2  sh = normalize(vec2(sunD.x, sunD.z) + 1e-5);
    float towardSun   = max(dot(dh, sh), 0.0);
    float horizonBand = smoothstep(0.55, 0.0, abs(dir.y));
    sky += vec3(1.30, 0.42, 0.10) * sunset * horizonBand * (0.20 + 0.80 * pow(towardSun, 2.5)) * 1.9;

    // Galaxia + estrellas + fugaces (noche).
#if GALAXY == 1
    sky += galaxyColor(dir) * night * up * GALAXY_STRENGTH;
#endif
    sky += vec3(0.55, 0.60, 0.85) * starField(dir) * night * up * STAR_BRIGHTNESS;
#if SHOOTING_STARS == 1
    sky += shootingStar(dir, frameTimeCounter) * night * up;
#endif

    // LUNA redonda con fase + resplandor.
    sky += MOON_COLOR * pow(max(dot(dir, moonD), 0.0), 60.0) * 0.5 * night;
    float mDisc  = celestialDisc(dir, moonD, MOON_SIZE);
    vec3  mPerp  = normalize(cross(moonD, vec3(0.0, 1.0, 0.0)) + vec3(1e-4));
    float mShift = (float(moonPhase) - 4.0) / 4.0;
    vec3  mShadowD = normalize(moonD + mPerp * mShift * MOON_SIZE * 1.7);
    float moon = clamp(mDisc - celestialDisc(dir, mShadowD, MOON_SIZE) * 0.95, 0.0, 1.0);
    sky = mix(sky, vec3(0.95, 0.96, 1.0), moon * night);

    // SOL redondo + resplandor (naranja al ponerse).
    vec3 sunGlowCol = mix(SUN_COLOR, vec3(1.30, 0.45, 0.12), sunset);
    sky += sunGlowCol * pow(max(dot(dir, sunD), 0.0), 40.0) * 0.6 * dayFactor;
    vec3 sunDiscCol = mix(vec3(2.0, 1.9, 1.6), vec3(2.50, 0.72, 0.18), sunset);
    sky = mix(sky, sunDiscCol, celestialDisc(dir, sunD, SUN_SIZE) * dayFactor);

    // Nubes (2 capas + sombreado = volumen). Capa 1 compartida con las
    // sombras de nube del terreno (lib/clouds.glsl).
#if CLOUDS == 1
    if (dir.y > 0.03) {
        vec2  cp1 = cameraPosition.xz + dir.xz * (160.0 / dir.y);
        float n1  = cloudLayer1(cp1, frameTimeCounter);
        vec2  cp2 = cameraPosition.xz + dir.xz * (300.0 / dir.y);
        float n2  = fbm(cp2 * 0.0004 + frameTimeCounter * (0.002 * CLOUD_SPEED) + 30.0, 3);
        float n   = n1 * 0.65 + n2 * 0.45;
        float cov = cloudCoverage(n, rainStrength) * smoothstep(0.03, 0.20, dir.y);
        float shade = smoothstep(0.30, 0.95, n1);
        vec3  cloudLo = mix(vec3(0.06, 0.08, 0.14), vec3(0.55, 0.58, 0.62), dayFactor);
        vec3  cloudHi = mix(vec3(0.30, 0.34, 0.46), vec3(1.00, 1.00, 1.00), dayFactor);
        // Tormenta: nubes grises y planas mientras llueve.
        cloudLo = mix(cloudLo, vec3(0.10, 0.11, 0.13) * (0.25 + 0.75 * dayFactor), rainStrength);
        cloudHi = mix(cloudHi, vec3(0.38, 0.40, 0.44) * (0.25 + 0.75 * dayFactor), rainStrength);
        sky = mix(sky, mix(cloudLo, cloudHi, shade), cov * 0.9);
    }
#endif

    // Relámpago: destello azulado en todo el cielo (uniform de Iris; en
    // OptiFine vale 0 y no hace nada).
#if LIGHTNING_FLASH == 1
    sky += vec3(0.75, 0.82, 1.10) * lightningBoltPosition.w * 1.2;
#endif
    return sky;
}

/* DRAWBUFFERS:0 */
void main() {
    float depth = texture2D(depthtex0, texcoord).r;
    vec3  scene = texture2D(colortex0, texcoord).rgb;

    if (depth < 1.0) {                       // hay geometría: dejar el píxel igual
        gl_FragData[0] = vec4(scene, 1.0);
        return;
    }

    vec3  viewPos    = screenToView(texcoord, depth);
    float dayFactor  = smoothstep(-0.08, 0.20, normalize(mat3(gbufferModelViewInverse) * sunPosition).y);
    gl_FragData[0] = vec4(renderSky(viewPos, dayFactor), 1.0);
}
