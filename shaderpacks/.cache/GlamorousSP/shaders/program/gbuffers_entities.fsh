#include "/lib/all_the_libs.glsl"

#include "/global/gbuffers.fsh"

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

void main() {
    Color = texture(gtexture, texcoord) * glcolor;

    if(Color.a < alphaTestRef) {
        discard;
    }
    
    Color.rgb = to_linear(Color.rgb);

    Color.xyz = mix(Color.rgb, entityColor.rgb, entityColor.a);
    vec3 PlayerPos = view_player(ViewPos, false);
    vec3 TweakedLM = tweak_lightmap(PlayerPos, LightmapCoords, gl_FragCoord.xy);
    Color.xyz *= TweakedLM;
}
