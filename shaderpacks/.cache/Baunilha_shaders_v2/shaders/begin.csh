#version 430 core
#define COMPUTE_SHADER
#include "/lib/cl/common.glsl"

const ivec3 workGroups = ivec3(524288, 1, 1);

layout (local_size_x = 1, local_size_y = 1) in;

void main() {
    uint id = gl_WorkGroupID.x;

    if (id < positionsChecked.length()) {
        positionsChecked[id] = 0;
    }
    if (id < maxChunks * maxVerticalChunks * maxChunks) {
        uint z = id / (maxChunks * maxVerticalChunks);
        uint y = (id / maxChunks) % maxVerticalChunks;
        uint x = id % maxChunks;
        lightColours.sizes[x][y][z] = 0;
    }

    // Limpa o buffer de luzes para sombras
    if (id == 0u) {
        blockLights.lightCount = 0u;
    }
    if (id < MAX_BLOCKLIGHTS) {
        blockLights.lights[id].position = vec3(0.0);
        blockLights.lights[id].radius = 0.0;
        blockLights.lights[id].color = vec3(0.0);
        blockLights.lights[id].intensity = 0.0;
    }
}
