#include "/lib/all_the_libs.glsl"
uniform sampler2D gtexture;
varying vec2 texcoord;
varying vec4 glcolor;
void main() {
	vec4 Color = texture2D(gtexture, texcoord) * glcolor;
	#ifdef ROUND_SUN
	discard;
	return;
	#endif
	Color.rgb = to_linear(Color.rgb);
	gl_FragData[0] = Color;
}
