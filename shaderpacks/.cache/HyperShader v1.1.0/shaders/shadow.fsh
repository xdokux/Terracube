#version 120

/* shadow.fsh — Escribe color de la sombra (shadowcolor0) y descarta píxeles
   transparentes (hojas, cristal) para que proyecten sombra calada. La
   profundidad se escribe automáticamente en shadowtex0/1. */

uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 vColor;

void main() {
    vec4 col = texture2D(gtexture, texcoord) * vColor;
    if (col.a < 0.1) discard;      // recorta el follaje en la sombra
    gl_FragData[0] = col;          // shadowcolor0 (tinte de sombras translúcidas)
}
