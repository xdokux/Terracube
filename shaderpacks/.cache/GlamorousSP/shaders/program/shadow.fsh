#include "/lib/all_the_libs.glsl"
in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS:0 */

void main() {
    if(texture(gtexture, texcoord).a < 0.1) discard;
}
