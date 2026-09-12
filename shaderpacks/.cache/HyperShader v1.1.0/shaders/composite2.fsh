#version 120

/* composite2.fsh — BLOOM paso 2: desenfoque gaussiano VERTICAL de colortex2.
   Resultado -> colortex3 (lo suma final.fsh). */

#include "/lib/common.glsl"

uniform sampler2D colortex2;
uniform float viewHeight;

varying vec2 texcoord;

/* DRAWBUFFERS:3 */
void main() {
#if BLOOM == 0
    gl_FragData[0] = vec4(0.0);
#else
    float py = (1.0 / viewHeight) * BLOOM_SPREAD;
    vec3 c = vec3(0.0);
    c += texture2D(colortex2, texcoord).rgb * 0.227;
    c += texture2D(colortex2, texcoord + vec2(0.0,  py)).rgb * 0.194;
    c += texture2D(colortex2, texcoord + vec2(0.0, -py)).rgb * 0.194;
    c += texture2D(colortex2, texcoord + vec2(0.0,  2.0 * py)).rgb * 0.121;
    c += texture2D(colortex2, texcoord + vec2(0.0, -2.0 * py)).rgb * 0.121;
    c += texture2D(colortex2, texcoord + vec2(0.0,  3.0 * py)).rgb * 0.054;
    c += texture2D(colortex2, texcoord + vec2(0.0, -3.0 * py)).rgb * 0.054;
    c += texture2D(colortex2, texcoord + vec2(0.0,  4.0 * py)).rgb * 0.016;
    c += texture2D(colortex2, texcoord + vec2(0.0, -4.0 * py)).rgb * 0.016;
    gl_FragData[0] = vec4(c, 1.0);
#endif
}
