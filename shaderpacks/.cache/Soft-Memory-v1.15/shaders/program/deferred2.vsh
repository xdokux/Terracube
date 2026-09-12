#include "/lib/all_the_libs.glsl"

varying vec2 texcoord;
varying vec2 LightmapCoords;
#include "/global/light_colors.vsh"
void main() {
    init_colors();
    gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    LightmapCoords = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
}
