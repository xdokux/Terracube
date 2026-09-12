#include "/lib/all_the_libs.glsl"
/* RENDERTARGETS: 0*/
varying vec2 texcoord;

void main() {
    vec4 color = texture(colortex0,texcoord);

    gl_FragData[0] = color;
}