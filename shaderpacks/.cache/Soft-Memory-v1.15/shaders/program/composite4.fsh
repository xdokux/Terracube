#include "/lib/all_the_libs.glsl"
#include "/global/post/bloom.glsl"

// Write to bloom buffer
const bool colortex0MipmapEnabled = true;

varying vec2 texcoord;

/* DRAWBUFFERS:1 */

void main() {
	vec3 Color = blur3x3(colortex0, texcoord).xyz;

	gl_FragData[0].rgb = Color;
}
