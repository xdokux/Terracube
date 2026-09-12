// ============================================
// blocklight_detection.csh - Detecta e registra luzes
// ============================================

#version 430 core

#define COMPUTE_SHADER
#include "/lib/settings.glsl"
#include "/lib/blocklight_shadow.glsl"

// ============================================
// CONFIGURAÇÕES
// ============================================
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

uniform vec3 cameraPosition;
uniform mat4 gbufferModelViewInverse;

// ============================================
// TEXTURAS DE BLOCOS (para detectar luzes)
// ============================================
uniform sampler2D colortex4; // Buffer de blocos

// ============================================
// FUNÇÃO PARA DETECTAR BLOCOS QUE EMITEM LUZ
// ============================================
bool isLightBlock(uint blockID) {
    const uint lightBlocks[32] = uint[32](
        89, 91, 138, 169, 213, 463, 464, 485, 544, 724,
        725, 726, 465, 466, 467, 468, 469, 470, 471, 473,
        474, 480, 481, 482, 483, 15001, 15002, 15003, 15007
    );

    for (int i = 0; i < 29; i++) {
        if (lightBlocks[i] == blockID) {
            return true;
        }
    }
    return false;
}

// ============================================
// FUNÇÃO PARA OBTER COR E RAIO DA LUZ
// ============================================
void getLightProperties(uint blockID, out vec3 color, out float radius) {
    if (blockID == 89 || blockID == 15003) { // Glowstone
        color = vec3(1.0, 0.43, 0.0);
        radius = 8.0;
    } else if (blockID == 91 || blockID == 15002) { // Jack o Lantern
        color = vec3(1.0, 0.54, 0.0);
        radius = 7.0;
    } else if (blockID == 169 || blockID == 15007) { // Sea Lantern
        color = vec3(0.0, 0.0, 1.0);
        radius = 8.0;
    } else if (blockID == 213) { // Magma Block
        color = vec3(1.0, 0.49, 0.0);
        radius = 4.0;
    } else if (blockID == 463) { // Lantern
        color = vec3(1.0, 0.54, 0.0);
        radius = 7.0;
    } else if (blockID == 464) { // Campfire
        color = vec3(1.0, 0.52, 0.0);
        radius = 6.0;
    } else if (blockID == 485) { // Shroomlight
        color = vec3(1.0, 0.33, 0.0);
        radius = 8.0;
    } else if (blockID == 465) { // Soul Lantern
        color = vec3(0.36, 0.78, 0.89);
        radius = 6.0;
    } else if (blockID == 466) { // Soul Torch
        color = vec3(0.36, 0.78, 0.89);
        radius = 5.0;
    } else if (blockID == 467 || blockID == 15001) { // Redstone Torch
        color = vec3(0.88, 0.23, 0.23);
        radius = 4.0;
    } else if (blockID == 470) { // Lava
        color = vec3(0.95, 0.47, 0.10);
        radius = 10.0;
    } else if (blockID == 471) { // Fire
        color = vec3(0.95, 0.47, 0.10);
        radius = 5.0;
    } else {
        color = vec3(1.0, 1.0, 1.0);
        radius = 5.0;
    }
}

// ============================================
// MAIN COMPUTE SHADER
// ============================================
void main() {
    // Posição do bloco no mundo
    ivec3 blockPos = ivec3(gl_GlobalInvocationID) + ivec3(floor(cameraPosition));
    vec3 worldPos = vec3(blockPos) + 0.5;

    // ============================================
    // ATENÇÃO: VOCÊ PRECISA DE UM JEITO DE LER O ID DO BLOCO
    // ============================================
    // Opção 1: Usar uma textura de blocos (colortex4)
    // uint blockID = uint(texture(colortex4, ...).r * 65535.0);

    // Opção 2: Usar um buffer de blocos
    // uint blockID = blockBuffer[blockPos];

    // Opção 3: SIMULAÇÃO PARA TESTE (descomente para testar)
    /*
     *   // Simula uma tocha em uma posição específica
     *   ivec3 torchPos = ivec3(0, 5, 0);
     *   if (blockPos == torchPos) {
     *       registerBlockLight(worldPos, 7.0, vec3(1.0, 0.54, 0.0), 1.0);
     *       return;
}
*/

    // ============================================
    // CÓDIGO REAL (quando tiver o buffer de blocos)
    // ============================================
    /*
     *   uint blockID = getBlockID(blockPos);
     *   if (isLightBlock(blockID)) {
     *       vec3 color;
     *       float radius;
     *       getLightProperties(blockID, color, radius);
     *       registerBlockLight(worldPos, radius, color, 1.0);
}
*/
}
