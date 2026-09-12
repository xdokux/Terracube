#include "/lib/all_the_libs.glsl"
#include "/global/post/bloom.glsl"

const bool colortex0MipmapEnabled = true;

varying vec2 texcoord;

/* DRAWBUFFERS:1 */

void main() {
	#ifdef BLOOM
	vec3 Color = blur3x3(colortex0, texcoord).xyz;
	#else
	vec3 Color = vec3(0.0);
	#endif

	gl_FragData[0].rgb = Color;
}
