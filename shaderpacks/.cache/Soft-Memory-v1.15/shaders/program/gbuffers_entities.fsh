#include "/lib/all_the_libs.glsl"

uniform sampler2D lightmap;
uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 ViewPos;

#include "/global/lighting.fsh"

/* RENDERTARGETS:0,8,9,11,7 */

void main() {
    vec4 Color = texture2D(gtexture, texcoord) * glcolor;
    Color.rgb = to_linear(Color.rgb);

    if (entityId == 10001) {
        Color.a = 1.0;
    }
    else {
        Color.xyz = mix(Color.rgb, entityColor.rgb, entityColor.a);
        vec3 worldPos = to_player_pos(ViewPos) + cameraPosition;
        vec3 TweakedLM = tweak_lightmap(worldPos);
        Color.xyz *= TweakedLM;
    }
    gl_FragData[0] = Color;
    gl_FragData[1] = vec4(0.0, 0.0, 0.0, 1.0);
    gl_FragData[2] = vec4(0.5, 0.5, 1.0, 1.0);
    gl_FragData[3] = vec4(1.0, 1.0, 1.0, 1.0);
    gl_FragData[4] = Color;
}
