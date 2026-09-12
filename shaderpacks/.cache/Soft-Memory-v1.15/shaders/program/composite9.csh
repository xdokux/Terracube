layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

#define CSH
#include "/lib/all_the_libs.glsl"

const ivec3 workGroups = ivec3(8,8,8);

void main() {
    ivec3 pos = ivec3(gl_GlobalInvocationID);

    int index = pos.x + (pos.y * 64) + (pos.z * 4096);
    voxels[index + OFFSET_A] = 0; // Clear A
    voxels[index + OFFSET_B] = 0; // Clear B
}