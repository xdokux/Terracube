#include "/lib/all_the_libs.glsl"

out vec2 texcoord;
#include "/global/lighting/light_colors.vsh"
void main() {
    init_colors();
    gl_Position = ftransform();
	texcoord = get_texcoord(gl_TextureMatrix[0], gl_MultiTexCoord0);

    // Guarantee the shadowmap runs for colored lights to work
    #if (defined COLORED_LIGHTS) && (!(defined DIMENSION_OVERWORLD) || !(defined DYNAMIC_SHADOWS))
    if(gl_VertexID == -1e6)
        texcoord.x = texture(shadowtex0, vec3(0));
    #endif
}
