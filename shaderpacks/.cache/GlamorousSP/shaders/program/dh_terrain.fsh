#define DH_TERRAIN

#include "/lib/all_the_libs.glsl"


#include "/global/gbuffers.fsh"

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

void main() {
    vec3 ScreenPos = vec3(gl_FragCoord.xy * resolutionInv, gl_FragCoord.z);
    vec3 PlayerPos = view_player(ViewPos, true);

    float Dither = bayer8(gl_FragCoord.xy);
    if (!transition_to_dh(PlayerPos, true, Dither)) {
        discard;
        return;
    }

    Color = glcolor;

    #ifdef DH_NOISE
        Color.rgb = dh_noise(PlayerPos, Color.rgb);
    #endif

    Color.rgb = to_linear(Color.rgb);

    vec3 TweakedLM = tweak_lightmap(PlayerPos, LightmapCoords, gl_FragCoord.xy);
    Color.xyz *= TweakedLM;
}
