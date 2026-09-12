#version 120
/* DRAWBUFFERS:01 */

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform vec4 entityColor;
uniform float alphaTestRef;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;

void main() {
    vec4 color = texture2D(gtexture, texcoord) * glcolor;
    color.rgb = mix(color.rgb, entityColor.rgb, entityColor.a);
    color *= texture2D(lightmap, lmcoord);

    if (color.a < alphaTestRef) {
        discard;
    }

    gl_FragData[0] = color;
    gl_FragData[1] = vec4(lmcoord, 0.0, 1.0);
}