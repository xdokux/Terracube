#define DH_TERRAIN

#include "/lib/all_the_libs.glsl"

uniform sampler2D lightmap;
uniform sampler2D gtexture;
varying vec2 texcoord;
varying vec4 glcolor;

#include "/global/lighting.fsh"

/* DRAWBUFFERS:0 */

void main() {
    vec3 ScreenPos = vec3(gl_FragCoord.xy * resolutionInv, gl_FragCoord.z);
    vec3 ViewPos = to_view_pos(ScreenPos, true);
    vec3 PlayerPos = to_player_pos(ViewPos);

    if (length(PlayerPos) < far - DH_CUTOFF) {
        discard;
        return;
    }

    vec4 Color = glcolor;

    #ifdef DH_NOISE
    vec3 WorldPos = PlayerPos + cameraPosition;
    vec3 NoisePos = floor(WorldPos * DH_NOISE_SIZE + 0.001) / DH_NOISE_SIZE;
    Color.rgb *= exp(-random3D(NoisePos) / 4) + 0.104;
    #endif

    Color.rgb = to_linear(Color.rgb);

    vec3 TweakedLM = tweak_lightmap();
    Color.xyz *= TweakedLM;
    gl_FragData[0] = Color;
}
