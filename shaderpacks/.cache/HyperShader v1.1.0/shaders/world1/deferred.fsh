#version 120

/* deferred.fsh (END) — Dibuja el cielo del End (void púrpura + galaxia lila +
   estrellas) ANTES de los translúcidos. Así el CRISTAL se mezcla por encima del
   cielo correcto (y no se ve el cielo vanilla / los puntitos a través de él). */

#include "/lib/common.glsl"
#include "/lib/spaceConversions.glsl"
#include "/lib/noise.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform mat4  gbufferModelViewInverse;
uniform float frameTimeCounter;

varying vec2 texcoord;

float eHash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 4.1414))) * 43758.5453); }
vec2  ePlane(vec3 d) { return d.xz / (abs(d.y) + 1.0); }

vec3 endSky(vec3 viewPos) {
    vec3 dir = normalize(mat3(gbufferModelViewInverse) * normalize(viewPos));

    float y = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
    vec3 sky = mix(vec3(0.035, 0.018, 0.060), vec3(0.090, 0.045, 0.150), y);

    vec3  gn = normalize(vec3(0.5, 0.42, 0.75));
    float band = pow(1.0 - clamp(abs(dot(dir, gn)) * 1.4, 0.0, 1.0), 2.2);
    vec2  pc = ePlane(dir) * 2.2;
    float dust  = fbm(pc + frameTimeCounter * 0.002, 3);
    float dust2 = fbm(pc * 2.5 + 7.0, 2);
    float density = band * smoothstep(0.28, 0.85, dust) * (0.4 + 0.6 * dust2);
    sky += mix(vec3(0.20, 0.08, 0.32), vec3(0.62, 0.32, 0.92), dust) * density * 1.3;

    vec2  sp = ePlane(dir) * 140.0;
    float sn = eHash(floor(sp)) * eHash(floor(sp * 2.0) + 3.0);
    float st = clamp(sn - 0.84, 0.0, 1.0);
    sky += vec3(0.72, 0.64, 0.93) * clamp(st * st * st * 700.0, 0.0, 3.0);

    return sky;
}

/* DRAWBUFFERS:0 */
void main() {
    float depth = texture2D(depthtex0, texcoord).r;
    vec3  color = texture2D(colortex0, texcoord).rgb;

    if (depth >= 1.0) {
        color = endSky(screenToView(texcoord, depth));
    }

    gl_FragData[0] = vec4(color, 1.0);
}
