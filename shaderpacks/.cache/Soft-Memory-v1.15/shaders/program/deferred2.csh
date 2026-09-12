layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

const ivec3 workGroups = ivec3(8,8,8);
#define CSH
#include "/lib/all_the_libs.glsl"

// Helper to safely get the packed data of a neighbor
int getNeighbor(ivec3 pos, ivec3 offset) {
    ivec3 nPos = pos + offset;
    if (nPos.x < 0 || nPos.x >= 64 || nPos.y < 0 || nPos.y >= 64 || nPos.z < 0 || nPos.z >= 64) return 0;
    return voxels[nPos.x + (nPos.y * 64) + (nPos.z * 4096) + OFFSET_B];
}

void main() {
    ivec3 pos = ivec3(gl_GlobalInvocationID);
    if (pos.x >= 64 || pos.y >= 64 || pos.z >= 64) return;

    int index = pos.x + (pos.y * 64) + (pos.z * 4096);
    int myData = voxels[index + OFFSET_B];
    int myID = myData >> 4;
    int myLevel = myData & 15;

    // If I am a solid block (1) or a max light source (level 15), I don't change.
    if (myID == 1 || myLevel == 15) {
        voxels[index + OFFSET_A] = myData;
        return;
    }

    int maxLevel = myLevel;
    int maxID = myID;

    // The 6 directions to check
    ivec3 offsets[6] = ivec3[](
        ivec3(1,0,0), ivec3(-1,0,0), ivec3(0,1,0),
        ivec3(0,-1,0), ivec3(0,0,1), ivec3(0,0,-1));

    // Look at all neighbors
    for (int i = 0; i < 6; i++) {
        int nData = getNeighbor(pos, offsets[i]);
        int nID = nData >> 4;
        int nLevel = nData & 15;

        // If neighbor is NOT solid, and has light to give
        if (nID != 1 && nLevel - 1 > maxLevel) {
            maxLevel = nLevel - 1; // Take their light minus 1
            maxID = nID;           // Steal their color ID
        }
    }

    // Write the new calculated light to Buffer B
    voxels[index + OFFSET_A] = (maxID << 4) | maxLevel;
}