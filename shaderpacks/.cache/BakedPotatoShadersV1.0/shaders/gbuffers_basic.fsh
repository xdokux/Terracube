#version 120

#include "/lib/settings.glsl"
#include "/lib/color.glsl"
#include "/lib/fog.glsl"

varying vec4 vColor;
varying vec3 vPlayerPosition;

void main() {
    vec3 color = srgbToLinearFast(vColor.rgb);
    color = applyAtmosphericFog(color, vPlayerPosition);
    gl_FragData[0] = vec4(color, vColor.a);
}
