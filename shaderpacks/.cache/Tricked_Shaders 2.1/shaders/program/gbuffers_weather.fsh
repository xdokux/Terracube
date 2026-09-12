#include "/lib/all_the_libs.glsl"

#include "/global/gbuffers.fsh"

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

void main() {
	Color = texture(gtexture, texcoord) * glcolor;
	if (Color.a < 0.1) {
		discard;
	}
	Color.rgb = to_linear(Color.rgb);

	vec3 PlayerPos = view_player(ViewPos, false);
	vec3 TweakedLM = tweak_lightmap(PlayerPos, LightmapCoords, texcoord, gl_FragCoord.xy);
	Color.xyz *= TweakedLM;
	

	Color = vec4(apply_saturation(Color.rgb, 0.2), 0.15);
}
