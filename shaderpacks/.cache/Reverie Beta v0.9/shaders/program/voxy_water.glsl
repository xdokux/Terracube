#include "/lib/all_the_libs.glsl"

#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/lighting/lighting.fsh"
#include "/generic/lighting/gbuffers_translucent.fsh"

void voxy_emitFragment(VoxyFragmentParameters param) {
    map_voxy_param_to_varying(param);
    init_frag_translucent(param);
}
