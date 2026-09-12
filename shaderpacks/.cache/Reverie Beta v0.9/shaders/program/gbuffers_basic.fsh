#include "/lib/all_the_libs.glsl"

#define GBUFFERS_BASIC

flat in vec4 glcolor_flat;

#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/lighting/lighting.fsh"
#include "/generic/lighting/gbuffers_translucent.fsh"

void main() {
    init_frag_translucent();
}
