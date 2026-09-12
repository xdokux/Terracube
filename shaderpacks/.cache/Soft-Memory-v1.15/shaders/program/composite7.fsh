#include "/lib/all_the_libs.glsl"
#include "/global/post/bloom.glsl"

varying vec2 texcoord;
varying vec2 PrevTilePos;

/* DRAWBUFFERS:1 */

void main() {
	gl_FragData[0].xyz = blur3x3(colortex1, PrevTilePos).xyz;
}
