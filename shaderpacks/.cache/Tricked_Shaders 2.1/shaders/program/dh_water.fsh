#define DH_TERRAIN

#include "/lib/all_the_libs.glsl"

#include "/global/gbuffers.fsh"
#include "/global/fog.glsl"

#include "/global/water.glsl"

vec4 get_translucent_basic(vec3 TweakedLM, vec3 ScreenPos, vec3 ViewPos) {
    vec4 Color = glcolor * texture(gtexture, texcoord);
    
    if (Color.a < 0.1) {
        discard;
    }

    vec3 PlayerPos = view_player(ViewPos, true);
    
    #ifdef DH_NOISE
        Color.rgb = dh_noise(PlayerPos, Color.rgb);
    #endif

    Color.rgb = to_linear(Color.rgb);
    Color.rgb *= TweakedLM;
    
    vec3 ViewPosN = normalize(ViewPos);
    vec3 SkyColor = get_sky_main(ViewPosN, normalize(PlayerPos), get_sun_glare(dot(ViewPosN, sunPosN)));
    Color.rgb = get_fog_main(ScreenPos, PlayerPos, Color.rgb, gl_FragCoord.z, SkyColor, dot(ViewPosN, sunPosN), dither(gl_FragCoord.xy), true);

    return Color;
}

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

void main() {
    vec3 ScreenPos = vec3(gl_FragCoord.xy*resolutionInv, gl_FragCoord.z);
    vec3 ViewPos = screen_view(ScreenPos, true); // Need to recalc here, water reflections break otherwise
    vec3 PlayerPos = view_player(ViewPos, true);

    float Dither = bayer8(gl_FragCoord.xy);

    if (!transition_to_dh(PlayerPos, true, Dither)) {
        discard;
    }

    float Depth = texture(depthtex1, ScreenPos.xy).x;

    if(Depth < 1) {
        discard;
    }

    vec3 TweakedLM = tweak_lightmap(PlayerPos, LightmapCoords, texcoord, gl_FragCoord.xy);

	if(material == 10001) {
		// glcolor gets set to water color in vsh
		#if WATER_TEXTURE_MODE == 2
		    vec4 BaseColor = vec4(glcolor.rgb*TweakedLM, glcolor.a);
		#else
            Color = texture(gtexture, texcoord);
            #ifdef DH_NOISE && WATER_TEXTURE_MODE < 2
                Color.rgb = dh_noise(PlayerPos, Color.rgb);
            #endif
            Color.rgb = to_linear(Color.rgb);
            #if WATER_TEXTURE_MODE == 1
                Color.rgb += 0.5;
                Color.a = 1; 
            #endif
            Color.rgb *= TweakedLM;
            vec4 BaseColor = Color * glcolor;
		#endif
		Color = get_fancy_water(ScreenPos, ViewPos, BaseColor, LightmapCoords.y, TBN, true);
	}
	else {
		Color = get_translucent_basic(TweakedLM, ScreenPos, ViewPos);
	}
}
