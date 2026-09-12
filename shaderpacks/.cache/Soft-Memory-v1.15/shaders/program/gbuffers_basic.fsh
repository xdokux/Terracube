#include "/lib/all_the_libs.glsl"

uniform sampler2D lightmap;
uniform sampler2D gtexture;


varying vec2 texcoord;
varying vec4 glcolor;
flat varying vec4 glcolor_flat;
varying vec3 ViewPos;

#include "/global/lighting.fsh"

/* DRAWBUFFERS:0 */

void main() {
    vec4 Color = glcolor_flat;

    // Workaround for selection box not rendering on optifine. I hate optifine.
    #ifdef GBUFFERS_TEXTURED
        Color *= texture2D(gtexture, texcoord);
    #endif
    vec3 worldPos = to_player_pos(ViewPos) + cameraPosition;
    Color.rgb = to_linear(Color.rgb);
    vec3 TweakedLM = tweak_lightmap(worldPos);
    Color.xyz *= TweakedLM;
    gl_FragData[0] = Color;
   
}
