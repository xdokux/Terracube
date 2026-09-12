#version 120
#define GBUFFER_FSH
#include "/lib/settings.glsl"
#include "/lib/gbuffer.glsl"
uniform vec4 entityColor;
void main() {
    gbufferFragment(0.3);
    gl_FragData[0].rgb = mix(gl_FragData[0].rgb, entityColor.rgb, entityColor.a);
}
