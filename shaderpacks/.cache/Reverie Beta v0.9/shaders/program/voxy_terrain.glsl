#define GBUFFERS_TERRAIN
#define VOXY_TERRAIN

#include "/lib/all_the_libs.glsl"

#include "/generic/lighting/gbuffers.fsh"

void voxy_emitFragment(VoxyFragmentParameters param) {
    map_voxy_param_to_varying(param);
    init_frag(param);
}
