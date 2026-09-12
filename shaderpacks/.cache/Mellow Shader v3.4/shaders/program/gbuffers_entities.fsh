#include "/lib/all_the_libs.glsl"

#include "/global/lighting/gbuffers.fsh"

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

void main() {
    mat3 TBN = tbn_decode(Normal, Tangent);
    float _PomShadow = 1;
    #if (defined PBR_POM) && (defined PBR_NORMAL)
        vec2 Texcoord = pom(TBN, _PomShadow);
        Color = textureGrad(gtexture, Texcoord, dCoordx, dCoordy);   
    #else
        vec2 Texcoord = texcoord;
        Color = texture(gtexture, Texcoord);   
    #endif

    Color *= glcolor;

    if(Color.a < alphaTestRef) {
        discard;
    }

    vec3 ScreenPos = vec3(gl_FragCoord.xy*resolutionInv, gl_FragCoord.z);
    vec3 PlayerPos = view_player(ViewPos, false);

    float Dither = dither(gl_FragCoord.xy);
    #if (defined DISTANT_HORIZONS) && (!defined VOXY)
        if (transition_to_dh(PlayerPos, false, Dither)) {
            discard;
        }
    #endif
    
    Color.rgb = to_linear(Color.rgb);

    Color.xyz = mix(Color.rgb, entityColor.rgb, entityColor.a);
    vec3 TweakedLM = tweak_lightmap(Color.rgb, PlayerPos, LightmapCoords, Texcoord, ScreenPos, TBN, Dither, _PomShadow);
    Color.xyz = TweakedLM;
}
