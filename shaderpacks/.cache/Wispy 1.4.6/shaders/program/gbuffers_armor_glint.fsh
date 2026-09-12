#include "/lib/all_the_libs.glsl"

uniform sampler2D texture;

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
	vec4 color = texture2D(texture, texcoord) * glcolor;

	float opacity;
	#ifdef DIMENSION_OVERWORLD
	opacity = ENCHANT_GLINT_OPACITY;
	#else
	opacity = 0.5;
	#endif

	color *= opacity;

	/* DRAWBUFFERS:0 */
	gl_FragData[0] = color; //gcolor
}
