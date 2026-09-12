#include "/lib/all_the_libs.glsl"
#include "/global/sky.glsl"
#include "/global/fog.glsl"

varying vec2 texcoord;

void main() {
    vec4 Color = texture(colortex0, texcoord);
    float Depth = texture(depthtex0, texcoord).r;

    bool IsDH = Depth > 0.0 && Depth < 1.0 && (Depth > 0.95);

    if (Depth >= 0.9999) {
        vec3 ScreenPos = vec3(texcoord, Depth);
        vec3 ViewPos = to_view_pos(ScreenPos, false);
        vec3 ViewPosN = fast_normalize(ViewPos);
        vec3 PlayerPos = to_player_pos(ViewPos);
        vec3 PlayerPosN = fast_normalize(PlayerPos);

        float VdotL = dot(ViewPosN, sunPosN);
        vec3 SunGlare = get_sun_glare(VdotL);
        vec3 SkyColor = get_sky_main(ViewPosN, PlayerPosN, SunGlare);

        #ifdef ROUND_SUN
        SkyColor += round_sun(VdotL);
        #endif

        Color.rgb += SkyColor;

        #if defined DIMENSION_OVERWORLD || defined DIMENSION_END
        if (PlayerPosN.y > 0.0) {
            Color.rgb += get_stars(PlayerPos);
        }
        #endif
    }
    else {
        vec3 ScreenPos = vec3(texcoord, Depth);
        vec3 ViewPos = to_view_pos(ScreenPos, IsDH);
        vec3 ViewPosN = fast_normalize(ViewPos);
        vec3 PlayerPos = to_player_pos(ViewPos);
        vec3 PlayerPosN = fast_normalize(PlayerPos);
        #if defined ATMOSPHERIC_FOG || defined BORDER_FOG || defined DIMENSION_END
        float VdotL = dot(ViewPosN, sunPosN);
        vec3 SunGlare = get_sun_glare(VdotL);
        vec3 SkyColor = get_sky_main(ViewPosN, PlayerPosN, SunGlare);

        float Dither = dither(gl_FragCoord.xy);
        Color.rgb = get_fog_main(ScreenPos, PlayerPos, Color.rgb, Depth, SkyColor, VdotL, Dither, IsDH);
        #endif
    }

    gl_FragData[0] = Color;
}
