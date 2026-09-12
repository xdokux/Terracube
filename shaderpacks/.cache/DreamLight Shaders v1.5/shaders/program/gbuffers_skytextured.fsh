#include "/lib/all_the_libs.glsl"
uniform sampler2D gtexture;

varying vec2 texcoord;

/* DRAWBUFFERS:0 */

void main() {
	#ifdef ROUND_SUN
	discard; return;
	#endif
	vec4 Color = texture2D(gtexture, texcoord);
	Color.rgb = to_linear(Color.rgb);

	Color.a = 1-rainStrength/2;
	gl_FragData[0] = Color;
}
