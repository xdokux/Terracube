#version 120

/* composite1.fsh — BLOOM paso 1: extrae lo brillante (HDR > umbral) y aplica
   un desenfoque gaussiano HORIZONTAL. Resultado -> colortex2. */

#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform float viewWidth;

varying vec2 texcoord;

/* DRAWBUFFERS:2 */
void main() {
#if BLOOM == 0
    gl_FragData[0] = vec4(0.0);
#else
    float px = (1.0 / viewWidth) * BLOOM_SPREAD;
    vec3 c = vec3(0.0);
    c += max(texture2D(colortex0, texcoord).rgb - BLOOM_THRESHOLD, 0.0) * 0.227;
    c += max(texture2D(colortex0, texcoord + vec2( px,      0.0)).rgb - BLOOM_THRESHOLD, 0.0) * 0.194;
    c += max(texture2D(colortex0, texcoord + vec2(-px,      0.0)).rgb - BLOOM_THRESHOLD, 0.0) * 0.194;
    c += max(texture2D(colortex0, texcoord + vec2( 2.0 * px, 0.0)).rgb - BLOOM_THRESHOLD, 0.0) * 0.121;
    c += max(texture2D(colortex0, texcoord + vec2(-2.0 * px, 0.0)).rgb - BLOOM_THRESHOLD, 0.0) * 0.121;
    c += max(texture2D(colortex0, texcoord + vec2( 3.0 * px, 0.0)).rgb - BLOOM_THRESHOLD, 0.0) * 0.054;
    c += max(texture2D(colortex0, texcoord + vec2(-3.0 * px, 0.0)).rgb - BLOOM_THRESHOLD, 0.0) * 0.054;
    c += max(texture2D(colortex0, texcoord + vec2( 4.0 * px, 0.0)).rgb - BLOOM_THRESHOLD, 0.0) * 0.016;
    c += max(texture2D(colortex0, texcoord + vec2(-4.0 * px, 0.0)).rgb - BLOOM_THRESHOLD, 0.0) * 0.016;
    gl_FragData[0] = vec4(c, 1.0);
#endif
}
