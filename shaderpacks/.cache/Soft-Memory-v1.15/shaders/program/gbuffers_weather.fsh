#include "/lib/all_the_libs.glsl"
uniform sampler2D lightmap;
uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 ViewPos;

#include "/global/lighting.fsh"

/* DRAWBUFFERS:0 */

void main() {
	vec4 Color = texture2D(gtexture, texcoord) * glcolor;
	if (Color.a < 0.1) {
		discard; return;
	}
	Color.rgb = to_linear(Color.rgb);

	float transparency=0.5;
	vec3 worldPos = to_player_pos(ViewPos) + cameraPosition;
	vec3 TweakedLM = tweak_lightmap(worldPos);
	Color.xyz *= TweakedLM;
	
	
	transparency=clamp(wetness,0.0,0.7);
	
	
	Color = vec4(apply_saturation(Color.rgb, 0.4), transparency);
	gl_FragData[0] = Color;
	
}
