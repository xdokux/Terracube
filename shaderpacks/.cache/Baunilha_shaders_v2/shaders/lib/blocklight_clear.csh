// ============================================
// blocklight_clear.csh - Limpa o buffer de luzes
// ============================================

#version 430 core

#define COMPUTE_SHADER
#include "/lib/settings.glsl"
#include "/lib/blocklight_shadow.glsl"

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

void main() {
    uint id = gl_GlobalInvocationID.x;

    // Limpa o contador de luzes
    if (id == 0u) {
        blockLights.lightCount = 0u;
    }

    // Limpa os dados das luzes (opcional)
    if (id < MAX_BLOCKLIGHTS) {
        blockLights.lights[id].position = vec3(0.0);
        blockLights.lights[id].radius = 0.0;
        blockLights.lights[id].color = vec3(0.0);
        blockLights.lights[id].intensity = 0.0;
    }
}
