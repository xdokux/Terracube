#include "/lib/all_the_libs.glsl"
#include "/global/light_colors.vsh"
varying vec2 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    init_colors();
}
