#include "/lib/all_the_libs.glsl"

#if VOXEL_DISTANCE == 64
const ivec3 workGroups = ivec3(16, 8, 16);
#elif VOXEL_DISTANCE == 96
const ivec3 workGroups = ivec3(24, 12, 24);
#elif VOXEL_DISTANCE == 128
const ivec3 workGroups = ivec3(32, 16, 32);
#elif VOXEL_DISTANCE == 192
const ivec3 workGroups = ivec3(48, 24, 48);
#elif VOXEL_DISTANCE == 256
const ivec3 workGroups = ivec3(64, 32, 64);
#endif
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

void main() {
    ivec3 Pos = ivec3(gl_GlobalInvocationID.xyz);
    ivec3 PrevPos = Pos - ivec3(previousCameraPosition) + ivec3(cameraPosition);

    vec4 Light = vec4(0);
    if(frameCounter % 2 == 0) {
        Light += texelFetchOffset(voxelImgSampler_a, PrevPos, 0, ivec3(0, -1, 0));
        Light += texelFetchOffset(voxelImgSampler_a, PrevPos, 0, ivec3(0, 1, 0));
        Light += texelFetchOffset(voxelImgSampler_a, PrevPos, 0, ivec3(-1, 0, 0));
        Light += texelFetchOffset(voxelImgSampler_a, PrevPos, 0, ivec3(1, 0, 0));
        Light += texelFetchOffset(voxelImgSampler_a, PrevPos, 0, ivec3(0, 0, -1));
        Light += texelFetchOffset(voxelImgSampler_a, PrevPos, 0, ivec3(0, 0, 1));
    } else {
        Light += texelFetchOffset(voxelImgSampler_b, PrevPos, 0, ivec3(0, -1, 0));
        Light += texelFetchOffset(voxelImgSampler_b, PrevPos, 0, ivec3(0, 1, 0));
        Light += texelFetchOffset(voxelImgSampler_b, PrevPos, 0, ivec3(-1, 0, 0));
        Light += texelFetchOffset(voxelImgSampler_b, PrevPos, 0, ivec3(1, 0, 0));
        Light += texelFetchOffset(voxelImgSampler_b, PrevPos, 0, ivec3(0, 0, -1));
        Light += texelFetchOffset(voxelImgSampler_b, PrevPos, 0, ivec3(0, 0, 1));
    }

    Light = max(vec4(0), Light / 6.1);

    if(frameCounter % 2 == 1) {
        imageStore(voxelImg_a, Pos, Light);
    } else {
        imageStore(voxelImg_b, Pos, Light);
    }
}