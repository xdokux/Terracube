#include "/lib/all_the_libs.glsl"

void main() {
    if (gl_VertexID == 0) {
        dataBuf.SunColor = get_direct_color(false, cameraPosition.y * 5);
        dataBuf.MoonColor = get_direct_color(true, cameraPosition.y * 5);
        dataBuf.SunColorVlClouds = get_direct_color(false, 1750);
        dataBuf.SunColorFlatClouds = get_direct_color(false, 4500);
        dataBuf.MoonColorVlClouds = get_direct_color(true, 1750);
        dataBuf.MoonColorFlatClouds = get_direct_color(true, 4500);
    }
    else if (gl_VertexID == 1) {
        #ifdef DIMENSION_OVERWORLD
        dataBuf.AmbientColor = get_ambient_color();
        #endif
    }
    gl_Position = vec4(-1);

    // Make the shadowmap run in the nether
    #ifdef VOXELISATION && DIMENSION_NETHER
    if(gl_VertexID == -1e6)
        dataBuf.AmbientColor = texture(shadowtex0, vec2(0)).gba;
    #endif
}
