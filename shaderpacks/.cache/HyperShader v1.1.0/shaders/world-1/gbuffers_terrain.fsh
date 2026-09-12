#version 120

/* gbuffers_terrain.fsh (NETHER) — VANILLA + lava emisiva.
   Usa el lightmap vanilla (sin sombras, sin grano) y mantiene la lava brillante.
   v1.1: luz dinámica de la antorcha en mano (aquí se agradece MUCHO). */

#include "/lib/common.glsl"
#include "/lib/lava.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform float frameTimeCounter;
uniform vec3  cameraPosition;
uniform int   heldBlockLightValue;
uniform int   heldBlockLightValue2;

varying vec2  texcoord;
varying vec2  lmcoord;
varying vec4  vColor;
varying vec3  worldPos;
varying float matID;

/* DRAWBUFFERS:01 */
void main() {
    vec4 albedo = texture2D(gtexture, texcoord) * vColor;
    if (albedo.a < 0.1) discard;

    vec3 lit;
    if (matID == 0.25) {
        lit = lavaFromTexture(albedo.rgb);     // lava tipo Solas (textura vanilla + grado cálido + HDR)
    } else {
        lit = albedo.rgb * texture2D(lightmap, lmcoord).rgb;                // luz vanilla

#if HANDLIGHT == 1
        float held = max(float(heldBlockLightValue), float(heldBlockLightValue2));
        if (held > 0.5) {
            float att = clamp(1.0 - length(worldPos - cameraPosition) / (held * 0.85), 0.0, 1.0);
            lit += albedo.rgb * vec3(1.00, 0.58, 0.24) * (att * att) * (held / 15.0) * 1.6 * HANDLIGHT_STRENGTH;
        }
#endif
    }

    gl_FragData[0] = vec4(lit, albedo.a);
    gl_FragData[1] = vec4(0.5, 0.5, 1.0, matID);
}
