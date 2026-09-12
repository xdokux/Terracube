#include "/lib/all_the_libs.glsl"

#include "/global/post/bloom.glsl"

varying vec2 texcoord;
varying vec2 PrevTilePos;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    gl_Position = gl_Position * 0.5 + 0.5;

    gl_Position.xy = adjust_vertex_position(64, 0.25, 128, gl_Position.xy);
    PrevTilePos = adjust_vertex_position(128, 0.5, 0, texcoord);

    gl_Position = gl_Position * 2 - 1;
}
