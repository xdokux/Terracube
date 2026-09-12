#define VOXY_TERRAIN

#include "/lib/all_the_libs.glsl"

#include "/global/gbuffers.fsh"
#include "/global/fog.glsl"
#include "/global/water.glsl"

vec4 get_translucent_basic(VoxyFragmentParameters param, vec3 TweakedLM, vec3 ScreenPos, vec3 ViewPos) {
	vec4 Color = vec4(glcolor.rgb, 1) * param.sampledColour;
	// if (Color.a < alphaTestRef) {
	// 	discard;
	// }
	Color.rgb *= glcolor.a;
	Color.rgb = to_linear(Color.rgb);
	Color.rgb *= TweakedLM;
	vec3 PlayerPos = view_player(ViewPos, false);
	vec3 ViewPosN = normalize(ViewPos);
	vec3 SkyColor = get_sky_main(ViewPosN, normalize(PlayerPos), get_sun_glare(dot(ViewPosN, sunPosN)));
    Color.rgb = get_fog_main(ScreenPos, PlayerPos, Color.rgb, gl_FragCoord.z, SkyColor, dot(ViewPosN, sunPosN), dither(gl_FragCoord.xy), false);

	return Color;
}

/* RENDERTARGETS:16 */
layout(location = 0) out vec4 Color;

void voxy_emitFragment(VoxyFragmentParameters param) {
    init_colors();
    map_voxy_param_to_varying(param);
	vec3 ScreenPos = vec3(gl_FragCoord.xy*resolutionInv, gl_FragCoord.z);
	vec3 ViewPos = screen_view(ScreenPos, true);
	vec3 PlayerPos = view_player(ViewPos, true);

	vec3 TweakedLM = tweak_lightmap(PlayerPos, LightmapCoords, gl_FragCoord.xy);

	if(material == 10001) {
        #if WATER_TEXTURE_MODE == 1 || WATER_TEXTURE_MODE == 2
        if(material == 10001) {
            const vec4 BaseColor = vec4(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE, f_WATER_ALPHA);
            glcolor.rgb = mix_preserve_c1lum(BaseColor.rgb, glcolor.rgb, f_BIOME_WATER_CONTRIBUTION);
            glcolor.rgb = to_linear(glcolor.rgb);
            glcolor.a = BaseColor.a;
        }
        #else
        glcolor.rgb = to_linear(glcolor.rgb);
        #endif
        
		#if WATER_TEXTURE_MODE == 2
		vec4 BaseColor = vec4(glcolor.rgb*TweakedLM, glcolor.a);
		#else
		Color = param.sampledColour;
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
		Color = get_translucent_basic(param, TweakedLM, ScreenPos, ViewPos);
	}
}
