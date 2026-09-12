#version 120

/* gbuffers_weather.vsh — Lluvia y nieve. Pasamos UV y color para poder
   atenuar las partículas en el fragment (que no sean una pared blanca). */

varying vec2 texcoord;
varying vec4 glColor;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glColor  = gl_Color;
}
