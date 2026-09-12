#include "/lib/all_the_libs.glsl"

#include "/global/post/bloom.glsl"

varying vec2 texcoord;
varying vec2 BloomTilePos;

void main() {
	gl_Position = ftransform();

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    BloomTilePos = adjust_vertex_position(128, 0.5, 0, texcoord);
}
