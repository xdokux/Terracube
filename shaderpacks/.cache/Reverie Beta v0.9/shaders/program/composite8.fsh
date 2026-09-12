#include "/lib/all_the_libs.glsl"
#include "/generic/post/bloom.glsl"

// Write to bloom buffer
const bool colortex0MipmapEnabled = true;

in vec2 texcoord;

/* RENDERTARGETS:10 */
layout(location = 0) out vec4 Color;


void main() {
	Color.rgb = blur6x6(colortex0, texcoord).rgb / 10;
	if(any(isnan(Color.rgb))) {
		Color.rgb = vec3(0);
	}
}
