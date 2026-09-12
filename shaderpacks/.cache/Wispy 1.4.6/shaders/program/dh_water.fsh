#define DH_TERRAIN
#include "/lib/all_the_libs.glsl"

uniform sampler2D lightmap;
uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
    vec3 ScreenPos = vec3(gl_FragCoord.xy * resolutionInv, gl_FragCoord.z);
    vec3 ViewPos   = to_view_pos(ScreenPos, true);
    vec3 PlayerPos = to_player_pos(ViewPos);

    float Dither = bayer8(gl_FragCoord.xy);
    if (!transition_to_dh(PlayerPos, true, Dither)) {
        discard;
        return;
    }

    vec4 Color = glcolor;

    float lightFactor = mix(nightStrength * 0.02, 0.9, dayStrength + sunriseStrength + sunsetStrength);
    Color.rgb *= lightFactor;

    #ifdef ATMOSPHERIC_FOG
        float dist = length(ViewPos);
        float fogFactor = exp(-dist * (fogAmount * 0.0015));
        vec3 fogColorMatch = mix(SKY_GROUND, SKY_TOP, clamp(normalize(ViewPos).y * 0.5 + 0.5, 0.0, 1.0));
        Color.rgb = mix(fogColorMatch, Color.rgb, fogFactor);
    #endif

    Color.rgb *= EXPOSURE;
    Color.rgb = apply_saturation(Color.rgb, SATURATION);
    Color.rgb = apply_vibrance(Color.rgb, VIBRANCE);
    Color.rgb = apply_contrast(Color.rgb, CONTRAST);

    gl_FragData[0] = Color;
}
