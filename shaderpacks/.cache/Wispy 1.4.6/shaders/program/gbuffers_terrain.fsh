#include "/lib/all_the_libs.glsl"

uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 MixedLights;

/* DRAWBUFFERS:0 */

void main() {
    vec4 Color = texture2D(gtexture, texcoord) * glcolor;

    Color.rgb = Color.rgb * Color.rgb * MixedLights;

    gl_FragData[0] = Color;
}
