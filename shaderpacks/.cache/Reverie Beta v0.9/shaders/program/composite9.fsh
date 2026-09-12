#include "/lib/all_the_libs.glsl"
#include "/generic/post/bloom.glsl"

in vec2 texcoord;
in vec2 PrevTilePos;

/* RENDERTARGETS:10 */

layout(location = 0) out vec4 Color;

void main() {
	Color.rgb = blur6x6(colortex10, PrevTilePos).rgb;
}
