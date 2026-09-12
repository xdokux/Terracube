#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

varying vec2 vTexCoord;
varying vec4 vColor;

void main() {
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < alphaTestRef) discard;
    gl_FragData[0] = vec4(srgbToLinearFast(texel.rgb) * 2.0, texel.a);
}
