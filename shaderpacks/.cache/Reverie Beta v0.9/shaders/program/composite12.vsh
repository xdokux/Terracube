#include "/lib/all_the_libs.glsl"

#include "/generic/post/bloom.glsl"

out vec2 texcoord;
out vec2 PrevTilePos;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    gl_Position = gl_Position * 0.5 + 0.5;

    gl_Position.xy = adjust_vertex_position(16, 0.03125, 256 + 128 + 64 + 32, gl_Position.xy);
    PrevTilePos = adjust_vertex_position(32, 0.0625, 256 + 128 + 64, texcoord);

    gl_Position = gl_Position * 2 - 1;
}
