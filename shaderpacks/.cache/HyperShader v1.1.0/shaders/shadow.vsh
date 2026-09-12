#version 120

/* shadow.vsh — Renderiza la escena desde el sol al shadow map (PILAR 3).
   Aplica la MISMA distorsión que usamos al muestrear (shadows.glsl) para
   concentrar resolución cerca del jugador. */

// shadows.glsl aporta distortShadow(). OJO: en las líneas #include de Iris
// NO puede haber comentarios ni nada tras la ruta, o falla al cargar el pack.
#include "/lib/common.glsl"
#include "/lib/shadows.glsl"

varying vec2 texcoord;
varying vec4 vColor;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor   = gl_Color;

    vec4 pos = ftransform();       // ya en clip-space de la sombra (proyección ortho)
    pos.xy = distortShadow(pos.xy);
    gl_Position = pos;
}
