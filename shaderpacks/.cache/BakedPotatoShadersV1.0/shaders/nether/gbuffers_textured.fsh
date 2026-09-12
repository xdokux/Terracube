#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"
#include "/lib/nether_fog.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

varying vec2 vTexCoord;
varying vec4 vColor;
varying vec3 vPlayerPosition;

void main() {
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < alphaTestRef) discard;
    vec3 color = srgbToLinearFast(texel.rgb);
    color = applyAtmosphericFog(color, vPlayerPosition);
    gl_FragData[0] = vec4(color, texel.a);
}
