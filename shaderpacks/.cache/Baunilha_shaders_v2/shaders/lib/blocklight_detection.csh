// ============================================
// blocklight_detection.csh - Detecta e registra luzes de bloco
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
uniform int frameCounter;

// ============================================
// TEXTURAS DE BLOCOS (para detectar luzes)
// ============================================
uniform sampler2D colortex4; // Buffer de blocos (IDs)
uniform sampler2D colortex5; // Buffer de metadados (opcional)

// ============================================
// BUFFER DE BLOCOS (alternativa à textura)
// ============================================
// layout(std430, binding = 4) readonly buffer blockBuffer {
//     uint blockIDs[];
// } blockData;

// ============================================
// FUNÇÃO PARA DETECTAR BLOCOS QUE EMITEM LUZ
// ============================================
bool isLightBlock(uint blockID) {
    // Lista completa de blocos que emitem luz
    const uint lightBlocks[40] = uint[40](
        89,    // Glowstone
        91,    // Jack o Lantern
        138,   // Beacon
        169,   // Sea Lantern
        213,   // Magma Block
        463,   // Lantern
        464,   // Campfire
        485,   // Shroomlight
        544,   // Crying Obsidian
        724,   // Pearlescent Froglight
        725,   // Verdant Froglight
        726,   // Ochre Froglight
        465,   // Soul Lantern
        466,   // Soul Torch/Fire
        467,   // Redstone Torch
        468,   // Furnace
        469,   // End Rod
        470,   // Lava
        471,   // Fire
        473,   // Conduit
        474,   // Respawn Anchor
        480,   // Redstone Block
        481,   // Copper Torch
        482,   // Copper Lantern
        483,   // Copper Bulb
        15728, // Firefly Bush
        15008, // Soul Lantern (categorized)
        15408, // Soul Fire (categorized)
        15001, // Redstone Torch (categorized)
        15014, // Furnace (categorized)
        15003, // Glowstone (categorized)
        15002, // Torch/Lantern/Campfire (categorized)
        15007, // Sea Lantern (categorized)
        15005, // Verdant Froglight (categorized)
        15009, // Pearlescent Froglight (categorized)
        15025, // End Rod/Beacon (categorized)
        15302, // Lava (categorized)
        15402, // Fire (categorized)
        15709  // Cave Vines (categorized)
    );

    for (int i = 0; i < 39; i++) {
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
    // Glowstone
    if (blockID == 89 || blockID == 15003) {
        color = vec3(1.0, 0.43, 0.0);
        radius = 8.0;
    }
    // Jack o Lantern / Lantern / Campfire / Torch
    else if (blockID == 91 || blockID == 463 || blockID == 464 || blockID == 15002) {
        color = vec3(1.0, 0.54, 0.0);
        radius = 7.0;
    }
    // Sea Lantern
    else if (blockID == 169 || blockID == 15007) {
        color = vec3(0.0, 0.0, 1.0);
        radius = 8.0;
    }
    // Magma Block
    else if (blockID == 213) {
        color = vec3(1.0, 0.49, 0.0);
        radius = 4.0;
    }
    // Shroomlight
    else if (blockID == 485) {
        color = vec3(1.0, 0.33, 0.0);
        radius = 8.0;
    }
    // Soul Lantern / Soul Torch / Soul Fire
    else if (blockID == 465 || blockID == 466 || blockID == 15008 || blockID == 15408) {
        color = vec3(0.36, 0.78, 0.89);
        radius = 6.0;
    }
    // Redstone Torch
    else if (blockID == 467 || blockID == 15001) {
        color = vec3(0.88, 0.23, 0.23);
        radius = 4.0;
    }
    // Furnace
    else if (blockID == 468 || blockID == 15014) {
        color = vec3(0.91, 0.46, 0.11);
        radius = 6.0;
    }
    // End Rod / Beacon
    else if (blockID == 469 || blockID == 138 || blockID == 15025) {
        color = vec3(1.0, 1.0, 1.0);
        radius = 7.0;
    }
    // Lava
    else if (blockID == 470 || blockID == 15302) {
        color = vec3(0.95, 0.47, 0.10);
        radius = 10.0;
    }
    // Fire
    else if (blockID == 471 || blockID == 15402) {
        color = vec3(0.95, 0.47, 0.10);
        radius = 5.0;
    }
    // Crying Obsidian
    else if (blockID == 544) {
        color = vec3(0.6, 0.0, 1.0);
        radius = 4.0;
    }
    // Froglights
    else if (blockID == 724 || blockID == 15009) { // Pearlescent
        color = vec3(1.0, 0.0, 1.0);
        radius = 8.0;
    } else if (blockID == 725 || blockID == 15005) { // Verdant
        color = vec3(0.0, 1.0, 0.0);
        radius = 8.0;
    } else if (blockID == 726) { // Ochre
        color = vec3(1.0, 1.0, 0.0);
        radius = 8.0;
    }
    // Conduit
    else if (blockID == 473) {
        color = vec3(0.40, 0.85, 0.88);
        radius = 8.0;
    }
    // Respawn Anchor
    else if (blockID == 474) {
        color = vec3(0.53, 0.12, 0.78);
        radius = 6.0;
    }
    // Redstone Block
    else if (blockID == 480) {
        color = vec3(1.0, 0.0, 0.0);
        radius = 4.0;
    }
    // Copper Torch / Lantern / Bulb
    else if (blockID == 481) {
        color = vec3(0.15, 0.93, 0.65);
        radius = 6.0;
    } else if (blockID == 482) {
        color = vec3(0.12, 0.95, 0.60);
        radius = 7.0;
    } else if (blockID == 483) {
        color = vec3(0.96, 0.55, 0.25);
        radius = 7.0;
    }
    // Firefly Bush / Cave Vines
    else if (blockID == 15728 || blockID == 15709) {
        color = vec3(0.87, 0.75, 0.27);
        radius = 5.0;
    }
    // Default
    else {
        color = vec3(1.0, 1.0, 1.0);
        radius = 5.0;
    }
}

// ============================================
// FUNÇÃO PARA LER ID DO BLOCO
// ============================================
uint getBlockID(ivec3 blockPos) {
    // ============================================
    // OPÇÃO 1: Usando textura (mais fácil)
    // ============================================
    // Converte posição do bloco para coordenadas de textura
    // Isso depende de como seu shader armazena os blocos
    // Exemplo: colortex4 contém IDs de blocos codificados
    /*
    vec2 uv = vec2(blockPos.x, blockPos.z) / 512.0; // Ajuste conforme necessário
    vec4 blockData = texture(colortex4, uv);
    return uint(blockData.r * 65535.0);
    */

    // ============================================
    // OPÇÃO 2: Usando buffer (mais eficiente)
    // ============================================
    // Descomente se estiver usando um buffer de blocos
    /*
    uint index = uint(blockPos.x + blockPos.y * 512 + blockPos.z * 512 * 512);
    return blockData.blockIDs[index];
    */

    // ============================================
    // OPÇÃO 3: SIMULAÇÃO PARA TESTE
    // ============================================
    // Descomente para testar com luzes fixas
    /*
    // Tocha na posição (0, 5, 0)
    if (blockPos.x == 0 && blockPos.y == 5 && blockPos.z == 0) {
        return 463; // Lantern ID
    }
    // Glowstone na posição (3, 4, 3)
    if (blockPos.x == 3 && blockPos.y == 4 && blockPos.z == 3) {
        return 89; // Glowstone ID
    }
    // Lava na posição (0, 3, 5)
    if (blockPos.x == 0 && blockPos.y == 3 && blockPos.z == 5) {
        return 470; // Lava ID
    }
    */

    // Se não for uma luz, retorna 0
    return 0u;
}

// ============================================
// MAIN COMPUTE SHADER
// ============================================
void main() {
    // ============================================
    // ZERA O BUFFER DE LUZES A CADA FRAME
    // ============================================
    // Nota: Isso deve ser feito em um compute shader separado
    // ou no início deste shader com um atomic exchange

    // ============================================
    // POSIÇÃO DO BLOCO NO MUNDO
    // ============================================
    ivec3 blockPos = ivec3(gl_GlobalInvocationID) + ivec3(floor(cameraPosition));
    vec3 worldPos = vec3(blockPos) + 0.5;

    // ============================================
    // LIMITE DE DISTÂNCIA (economiza performance)
    // ============================================
    float distToPlayer = length(worldPos - cameraPosition);
    if (distToPlayer > 32.0) return; // Só processa blocos próximos

    // ============================================
    // LÊ O ID DO BLOCO
    // ============================================
    uint blockID = getBlockID(blockPos);

    // ============================================
    // VERIFICA SE É UMA LUZ
    // ============================================
    if (isLightBlock(blockID)) {
        vec3 color;
        float radius;
        getLightProperties(blockID, color, radius);

        // ============================================
        // REGISTRA A LUZ NO BUFFER
        // ============================================
        registerBlockLight(worldPos, radius, color, 1.0);
    }
}
