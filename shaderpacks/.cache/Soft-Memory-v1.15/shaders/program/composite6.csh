layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;


layout(std430, binding = 0) buffer VoxelGrid {
    int voxels[262144]; 
};

const ivec3 workGroups = ivec3(8,8,8);

void main() {

    ivec3 pos = ivec3(gl_GlobalInvocationID);
    
   
    int index = pos.x + (pos.y * 64) + (pos.z * 4096);
    

    voxels[index] = 0;
}