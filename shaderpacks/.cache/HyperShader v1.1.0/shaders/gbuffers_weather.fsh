#version 120

/* gbuffers_weather.fsh — Atenúa la nieve/lluvia: menos opaca y algo menos
   brillante, para que al nevar no se vea una pared blanca cegadora. */

uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 glColor;

/* DRAWBUFFERS:0 */
void main() {
    vec4 c = texture2D(gtexture, texcoord) * glColor;
    c.a   *= 0.45;   // más transparente => menos "pared" de nieve
    c.rgb *= 0.80;   // un pelín menos brillante
    gl_FragData[0] = c;
}
