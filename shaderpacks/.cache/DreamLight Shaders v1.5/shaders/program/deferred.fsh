#include "/lib/all_the_libs.glsl"

#include "/global/sky.glsl"
#include "/global/fog.glsl"
#include "/global/post/ssao.glsl"

// Sky, Clouds, etc

varying vec2 texcoord;

/* DRAWBUFFERS:0 */

void main() {
    vec4 Color = texture2D(colortex0, texcoord);
    bool IsDH;
    float Depth = get_depth(texcoord, IsDH);
    vec3 ScreenPos = vec3(texcoord, Depth);
    vec3 ViewPos = to_view_pos(ScreenPos, IsDH);

    vec3 PlayerPos = mat3(gbufferModelViewInverse) * ViewPos;

    vec3 ViewPosN = normalize(ViewPos);
    vec3 PlayerPosN = normalize(PlayerPos);

    float VdotL = dot(ViewPosN, sunPosN);
    vec3 SunGlare = get_sun_glare(VdotL);
    vec3 SkyColor = get_sky_main(ViewPosN, PlayerPosN, SunGlare);

    if (Depth >= 1) {
        #ifndef DIMENSION_OVERWORLD
        Color = vec4(0, 0, 0, 1);
        #elif defined ROUND_SUN
        SkyColor += round_sun(VdotL);
        #endif

        #ifdef DEBUG_OVERRIDE_SKY
        Color.rgb = SkyColor;
        #else
        Color.rgb += SkyColor;
        #endif

        if (PlayerPos.y > 0) {
            #if defined DIMENSION_OVERWORLD || defined DIMENSION_END
            Color.rgb += get_stars(PlayerPos);
            #endif

            #if defined DIMENSION_OVERWORLD && defined FANCY_CLOUDS
            Color.rgb = get_clouds(PlayerPos, PlayerPosN, SunGlare, Color.rgb);
            #endif
        }
    }
    #ifdef SSAO
    else if (Depth >= 0.56) { // Skip hand & sky
        Color.rgb = ssao(Color.rgb, ViewPos);
    }
    #endif

    if (Depth >= 0.56) { // Skip JUST the hand
        Color.rgb = get_fog_main(PlayerPos, Color.rgb, Depth, SkyColor);
    }

    gl_FragData[0] = Color;
}
