#include "/lib/all_the_libs.glsl"

#include "/global/gbuffers.fsh"
#include "/global/fog.glsl"
#include "/global/water.glsl"

vec4 get_translucent_basic(vec3 TweakedLM, vec3 ScreenPos, vec3 ViewPos) {
	vec4 Color = vec4(glcolor.rgb, 1) * texture(gtexture, texcoord);
	if (Color.a < alphaTestRef) {
		discard;
	}
	Color.rgb *= glcolor.a;
	Color.rgb = to_linear(Color.rgb);
	Color.rgb *= TweakedLM;
	vec3 PlayerPos = view_player(ViewPos, false);
	vec3 ViewPosN = normalize(ViewPos);
	vec3 SkyColor = get_sky_main(ViewPosN, normalize(PlayerPos), get_sun_glare(dot(ViewPosN, sunPosN)));
    Color.rgb = get_fog_main(ScreenPos, PlayerPos, Color.rgb, gl_FragCoord.z, SkyColor, dot(ViewPosN, sunPosN), dither(gl_FragCoord.xy), false);

	return Color;
}

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

void main() {
	vec3 ScreenPos = vec3(gl_FragCoord.xy*resolutionInv, gl_FragCoord.z);
	vec3 ViewPos = screen_view(ScreenPos, false);
	vec3 PlayerPos = view_player(ViewPos, false);

	#if (defined DISTANT_HORIZONS) && (!defined VOXY)
	float Dither = bayer8(gl_FragCoord.xy);

	// this pass now comes AFTER dh_water for some reason???????????????????????
	// i give up
    if (transition_to_dh(PlayerPos, false, Dither - 1.5)) {
		#if MC_VERSION > 12108
        float Diff = texture(dhDepthTex1, ScreenPos.xy).x - texture(dhDepthTex0, ScreenPos.xy).x;

		if(Diff > 1e-6)
		#endif
			discard;
    }
    #endif

	vec3 TweakedLM = tweak_lightmap(PlayerPos, LightmapCoords, gl_FragCoord.xy);

	if(material == 10001) {
		// glcolor gets set to water color in vsh
		#if WATER_TEXTURE_MODE == 2
		vec4 BaseColor = vec4(glcolor.rgb*TweakedLM, glcolor.a);
		#else
		Color = texture(gtexture, texcoord);
		Color.rgb = to_linear(Color.rgb);
		#if WATER_TEXTURE_MODE == 1
		Color.rgb += 0.5;
		Color.a = 1; 
		#endif
		Color.rgb *= TweakedLM;
		vec4 BaseColor = Color * glcolor;
		#endif
		Color = get_fancy_water(ScreenPos, ViewPos, BaseColor, LightmapCoords.y, TBN, false);
	}
	else {
		Color = get_translucent_basic(TweakedLM, ScreenPos, ViewPos);
	}
}
