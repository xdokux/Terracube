#define DH_TERRAIN
#include "/lib/all_the_libs.glsl"
uniform sampler2D gtexture;
varying vec2 texcoord;
varying vec4 glcolor;
void main() {
    vec2 ScreenPosXY = gl_FragCoord.xy * resolutionInv;
    vec3 ViewPos = to_view_pos(vec3(ScreenPosXY, gl_FragCoord.z), true);
    vec3 PlayerPos = to_player_pos(ViewPos);
    if (!transition_to_dh(PlayerPos, true, bayer8(gl_FragCoord.xy))) {
        discard; return;
    }
    vec4 Color = glcolor * texture2D(gtexture, texcoord);
    #ifdef DH_NOISE
        Color.rgb = dh_noise(PlayerPos, Color.rgb);
    #endif
    float lightFactor = mix(nightStrength * 0.05, 1.0, 1.0 - nightStrength);
    Color.rgb = to_linear(Color.rgb) * lightFactor * EXPOSURE;
    #ifdef ATMOSPHERIC_FOG
        float fogFactor = clamp(exp(-length(ViewPos) * (fogAmount * 0.0015)), 0.0, 1.0);
        Color.rgb = mix(SKY_GROUND, Color.rgb, fogFactor);
    #endif
    Color.rgb = apply_saturation(Color.rgb, SATURATION);
    Color.rgb = apply_vibrance(Color.rgb, VIBRANCE);
    Color.rgb = apply_contrast(Color.rgb, CONTRAST);
    gl_FragData[0] = Color;
}
