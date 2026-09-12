#include "/lib/all_the_libs.glsl"

#include "/generic/post/bloom.glsl"

out vec2 texcoord;
out vec2 BloomTilePos;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	BloomTilePos = adjust_vertex_position(256, 0.5, 0, texcoord);
}
