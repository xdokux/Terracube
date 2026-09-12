#define DH_TERRAIN

#include "/lib/all_the_libs.glsl"

#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/lighting/lighting.fsh"
#include "/generic/lighting/gbuffers_translucent.fsh"

void main() {
    init_frag_translucent();
}
