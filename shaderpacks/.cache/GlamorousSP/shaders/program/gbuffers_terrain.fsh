#include "/lib/all_the_libs.glsl"


#include "/global/gbuffers.fsh"

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

vec3 end_portal_shader(vec3 WorldPos, vec3 PlayerPosN, vec3 WorldNormal) {
    vec2 Pos, Dir;
    if(abs(WorldNormal.y) < 0.01) {
        if(abs(WorldNormal.x) < 0.5) {
            Pos = WorldPos.xy * sign(-WorldNormal.z);
            Dir = PlayerPosN.xy  / PlayerPosN.z;
        } else {
            Pos = WorldPos.yz * sign(-WorldNormal.x);
            Dir = PlayerPosN.yz / PlayerPosN.x;
        }
    } else {
        Pos = WorldPos.xz;
        Dir = PlayerPosN.xz / PlayerPosN.y * sign(-WorldNormal.y);
    }

    vec3 StarColor = to_linear(vec3(0.5, 0.7, 0.5) * 2.);
    vec3 StarColorChange = to_linear(vec3(0.6, 0.55, 0.8));
    vec2 Wind = vec2(1, 1);

    Dir *= 0.2;
    for(int i = 1; i <= 6; i++) {
        Dir *= 1.75;
        Pos += Dir;
        StarColor *= StarColorChange;
        vec2 StarPos = floor(Pos * 15 + Wind * (frameTimeCounter + 100)) / 10000;
        float Noise = random(StarPos);
        if(Noise > 0.97) {
            return StarColor;
        }
        Wind.y *= Wind.x;
        Wind.x *= -1;
        
    }
    return vec3(0);
}

void main() {
    Color = texture(gtexture, texcoord) * vec4(glcolor.rgb, 1);

    if(Color.a < alphaTestRef) {
        discard;
    }

    Color.rgb *= glcolor.a;

    vec3 ScreenPos = vec3(gl_FragCoord.xy*resolutionInv, gl_FragCoord.z);
    vec3 PlayerPos = view_player(ViewPos, false);

    #if (defined DISTANT_HORIZONS) && (!defined VOXY)
    float Dither = bayer8(gl_FragCoord.xy);
        if (transition_to_dh(PlayerPos, false, Dither)) {
            discard;
        }
    #endif

    // End portal effect
    if(material == 10007) {
        Color.rgb = end_portal_shader(PlayerPos + cameraPosition, normalize(PlayerPos), view_player(TBN[2], false));
    } else {
        Color.rgb = to_linear(Color.rgb);

        vec3 TweakedLM = tweak_lightmap(PlayerPos, LightmapCoords, gl_FragCoord.xy);
        Color.xyz *= TweakedLM;
    }    
}
