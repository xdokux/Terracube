#ifndef COLOUR_COMMON_GLSL
#define COLOUR_COMMON_GLSL

#include "/lib/cl/lights.glsl"

// ============================================
// DECLARAÇÕES DE UNIFORMS (precisa vir antes do blocklight_shadow.glsl)
// ============================================
#ifndef COMPUTE_SHADER
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 cameraPosition;
uniform sampler2D depthtex0;
#endif

// ============================================
// INCLUI O SISTEMA DE SOMBRAS PARA LUZES DE BLOCO
// ============================================
#include "/lib/blocklight_shadow.glsl"

// ============================================
// CONFIGURAÇÕES OTIMIZADAS
// ============================================
#define BLOCK_LIGHTS
#define COLOURED_LIGHTS_RENDER_DISTANCE 16
#define COLOURED_LIGHTS_RENDER_DISTANCE_VERTICAL 16
#define MAX_COLOURED_LIGHTS 128
#define COLOUR_INTENSITY 1.5

// ============================================
// ESTRUTURAS OTIMIZADAS (alinhamento para cache)
// ============================================
struct LightColourBlock {
    ivec3 blockPos;
    uint lightID;
};

struct LightData {
    vec3 position;
    vec3 colour;
    float intensity;
    float radius;
    bool natural;
};

// ============================================
// CONSTANTES PRÉ-CALCULADAS
// ============================================
const uint maxChunks = COLOURED_LIGHTS_RENDER_DISTANCE;
const uint maxVerticalChunks = COLOURED_LIGHTS_RENDER_DISTANCE_VERTICAL;
const uint localBlockOffset = (maxChunks / 2) * 16;
const uint localBlockVerticalOffset = (maxVerticalChunks / 2) * 16;
const uint maxColouredLightsChunk = MAX_COLOURED_LIGHTS;
const vec3 centreOffset = vec3(0.5);
const float midblockUnit = 64.0;

// ============================================
// BUFFERS (mantidos)
// ============================================
layout (std430, binding = 0) coherent buffer positionsCheckedBuffer {
    uint[] positionsChecked;
};

layout(std430, binding = 1) coherent buffer lightColoursBuffer {
    uint[maxChunks][maxVerticalChunks][maxChunks] sizes;
    LightColourBlock[][maxColouredLightsChunk] lights;
} lightColours;

// ============================================
// FUNÇÕES DE POSIÇÃO OTIMIZADAS
// ============================================

ivec3 worldPosToBlockPos(vec3 worldPos, vec3 midBlock) {
    return ivec3(floor(worldPos + (midBlock / midblockUnit)));
}

ivec3 blockPosToChunkPos(ivec3 blockPos) {
    return blockPos >> 4; // Equivalente a floor(blockPos / 16) (mais rápido)
}

ivec3 blockPosToLocalPos(ivec3 blockPos) {
    ivec3 cameraBlockPos = ivec3(floor(cameraPosition));
    return ivec3(
        blockPos.x - cameraBlockPos.x + int(localBlockOffset),
                 blockPos.y - cameraBlockPos.y + int(localBlockVerticalOffset),
                 blockPos.z - cameraBlockPos.z + int(localBlockOffset)
    );
}

bool localChunkPosOutOfBounds(ivec3 localChunkPos) {
    return (localChunkPos.x < 0 || localChunkPos.y < 0 || localChunkPos.z < 0 ||
    localChunkPos.x >= int(maxChunks) ||
    localChunkPos.y >= int(maxVerticalChunks) ||
    localChunkPos.z >= int(maxChunks));
}

// ============================================
// POS MARKED OTIMIZADO (com early exit)
// ============================================

bool posMarked(ivec3 localBlockPos) {
    ivec3 localChunkPos = blockPosToChunkPos(localBlockPos);
    if (localChunkPosOutOfBounds(localChunkPos)) {
        return true;
    }

    // Otimização: Pré-calcula índices
    uint sector = uint(((localBlockPos.y & 15) * 8) + ((localBlockPos.z & 15) >> 1));
    uint positionsCheckedIndex = ((localChunkPos.x * maxVerticalChunks + localChunkPos.y) * maxChunks + localChunkPos.z) * 128 + sector;

    if (positionsCheckedIndex >= positionsChecked.length()) {
        return true;
    }

    uint bit = uint((localBlockPos.x & 15) + ((localBlockPos.z & 1) << 4));
    uint bitmask = 1u << bit;

    // Early exit: se já está marcado
    if ((positionsChecked[positionsCheckedIndex] & bitmask) != 0u) {
        return true;
    }

    // Atomic OR para marcar
    uint original = atomicOr(positionsChecked[positionsCheckedIndex], bitmask);
    return ((original & bitmask) != 0u);
}

// ============================================
// APPLY COLOURED LIGHT OTIMIZADO
// ============================================

vec4 applyColouredLight(vec4 baseColour, vec4 startLight, vec3 worldPos, ivec3 localChunkPos) {
    if (localChunkPosOutOfBounds(localChunkPos)) {
        baseColour *= startLight;
        return baseColour;
    }

    vec3 colours = vec3(0.0);
    float colourCount = 0.0;
    float maxWeight = 0.0;

    // Otimização: Loop desenrolado parcialmente
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            for (int z = -1; z <= 1; z++) {
                ivec3 chunk = localChunkPos + ivec3(x, y, z);
                if (localChunkPosOutOfBounds(chunk)) continue;

                uint size = lightColours.sizes[chunk.x][chunk.y][chunk.z];
                if (size == 0u) continue; // Early exit se não há luzes

                uint chunkIndex = uint(chunk.x + int(maxChunks) * (chunk.y + int(maxVerticalChunks) * chunk.z));
                uint maxIndex = min(size, maxColouredLightsChunk);

                for (uint i = 0u; i < maxIndex; i++) {
                    LightColourBlock lightBlock = lightColours.lights[chunkIndex][i];

                    // Pula se lightID for inválido
                    if (lightBlock.lightID >= colouredLights.length()) continue;

                    ColouredLight light = colouredLights[lightBlock.lightID];
                    vec3 lightPos = vec3(lightBlock.blockPos) + centreOffset;

                    // Otimização: Manhattan distance com early exit
                    float dx = abs(lightPos.x - worldPos.x);
                    if (dx >= light.blockLightLevel) continue;
                    float dy = abs(lightPos.y - worldPos.y);
                    if (dy >= light.blockLightLevel) continue;
                    float dz = abs(lightPos.z - worldPos.z);
                    if (dz >= light.blockLightLevel) continue;

                    float d = dx + dy + dz;
                    if (d < light.blockLightLevel) {
                        float weight = ((light.blockLightLevel - d) / light.blockLightLevel) * COLOUR_INTENSITY;
                        float weightSq = weight * weight;
                        colours += light.lightColour * weightSq;
                        colourCount += weight;
                        maxWeight = max(maxWeight, weight);

                        if (!light.natural) {
                            startLight = max(startLight, vec4(weight));
                        }
                    }
                }
            }
        }
    }

    // Aplica luz base
    baseColour *= startLight;

    // Aplica luz colorida (otimizado)
    if (colourCount > 0.01) {
        vec3 averageColour = colours / colourCount;
        baseColour += baseColour * vec4(averageColour, 0.0);
    }

    return baseColour;
}

// ============================================
// VERSÃO OTIMIZADA COM CACHE (mais rápida)
// ============================================

// Cache para luzes próximas (reduz cálculos)
#define LIGHT_CACHE_SIZE 16
vec3 lightCachePositions[LIGHT_CACHE_SIZE];
vec3 lightCacheColours[LIGHT_CACHE_SIZE];
float lightCacheIntensities[LIGHT_CACHE_SIZE];
int lightCacheCount = 0;

vec4 applyColouredLightCached(vec4 baseColour, vec4 startLight, vec3 worldPos, ivec3 localChunkPos) {
    if (localChunkPosOutOfBounds(localChunkPos)) {
        baseColour *= startLight;
        return baseColour;
    }

    vec3 colours = vec3(0.0);
    float colourCount = 0.0;

    // Usa cache se disponível
    for (int i = 0; i < lightCacheCount && i < LIGHT_CACHE_SIZE; i++) {
        vec3 lightPos = lightCachePositions[i];
        float dx = abs(lightPos.x - worldPos.x);
        float dy = abs(lightPos.y - worldPos.y);
        float dz = abs(lightPos.z - worldPos.z);
        float d = dx + dy + dz;

        float radius = lightCacheIntensities[i];
        if (d < radius) {
            float weight = ((radius - d) / radius) * COLOUR_INTENSITY;
            float weightSq = weight * weight;
            colours += lightCacheColours[i] * weightSq;
            colourCount += weight;
        }
    }

    baseColour *= startLight;
    if (colourCount > 0.01) {
        vec3 averageColour = colours / colourCount;
        baseColour += baseColour * vec4(averageColour, 0.0);
    }
    return baseColour;
}

// ============================================
// VERSÃO COM EARLY EXIT (máxima performance)
// ============================================

vec4 applyColouredLightFast(vec4 baseColour, vec4 startLight, vec3 worldPos, ivec3 localChunkPos) {
    // Early exit: se não há luzes no chunk
    if (localChunkPosOutOfBounds(localChunkPos)) {
        baseColour *= startLight;
        return baseColour;
    }

    // Verifica rapidamente se há luzes próximas
    bool hasLight = false;
    for (int x = -1; x <= 1 && !hasLight; x++) {
        for (int y = -1; y <= 1 && !hasLight; y++) {
            for (int z = -1; z <= 1 && !hasLight; z++) {
                ivec3 chunk = localChunkPos + ivec3(x, y, z);
                if (!localChunkPosOutOfBounds(chunk)) {
                    if (lightColours.sizes[chunk.x][chunk.y][chunk.z] > 0u) {
                        hasLight = true;
                    }
                }
            }
        }
    }

    if (!hasLight) {
        return baseColour * startLight;
    }

    // Se tem luz, processa normalmente
    return applyColouredLight(baseColour, startLight, worldPos, localChunkPos);
}

// ============================================
// VERTEX SHADER FUNCTIONS OTIMIZADAS
// ============================================

#ifdef VERTEX
vec3 modelToWorldSpace(vec3 modelPos) {
    vec3 viewPos = (gl_ModelViewMatrix * vec4(modelPos, 1.0)).xyz;
    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    return feetPlayerPos + cameraPosition;
}

vec4 worldToClipSpace(vec3 worldPos) {
    vec3 feetPlayerPos = worldPos - cameraPosition;
    vec3 viewPos = (gbufferModelView * vec4(feetPlayerPos, 1.0)).xyz;
    return gbufferProjection * vec4(viewPos, 1.0);
}

void registerPos(ivec3 blockPos, uint id) {
    ivec3 localBlockPos = blockPosToLocalPos(blockPos);
    ivec3 localChunkPos = blockPosToChunkPos(localBlockPos);

    if (posMarked(localBlockPos)) {
        return;
    }

    // ============================================
    // REGISTRA LUZ NO BUFFER DE SOMBRAS (ray marching)
    // ============================================
    // Só executa uma vez por bloco graças ao posMarked acima
    ColouredLight light = colouredLights[id];
    registerBlockLight(vec3(blockPos) + 0.5 - cameraPosition, float(light.blockLightLevel), light.lightColour, 1.0);

    uint currentSize = lightColours.sizes[localChunkPos.x][localChunkPos.y][localChunkPos.z];
    if (currentSize >= maxColouredLightsChunk) {
        return;
    }

    uint localIndex = atomicAdd(lightColours.sizes[localChunkPos.x][localChunkPos.y][localChunkPos.z], 1u);
    if (localIndex >= maxColouredLightsChunk) {
        return;
    }

    uint chunkIndex = uint(localChunkPos.x + int(maxChunks) * (localChunkPos.y + int(maxVerticalChunks) * localChunkPos.z));
    lightColours.lights[chunkIndex][localIndex].blockPos = blockPos;
    lightColours.lights[chunkIndex][localIndex].lightID = id;
}

void lightCheck(vec3 midBlock, ivec2 mcEntity) {
    vec3 worldPos = modelToWorldSpace(gl_Vertex.xyz);
    ivec3 blockPos = worldPosToBlockPos(worldPos, midBlock);

    uint blockID = uint(mcEntity.x);
    uint numLights = colouredLights.length();

    // Otimização: Verifica primeiro luzes naturais
    #ifdef BLOCK_LIGHTS
    for (uint i = 0u; i < numLights; i++) {
        if (colouredLights[i].blockID == blockID) {
            registerPos(blockPos, i);
            return; // Early exit após encontrar
        }
    }
    #else
    for (uint i = 0u; i < numLights; i++) {
        if (colouredLights[i].natural && colouredLights[i].blockID == blockID) {
            registerPos(blockPos, i);
            return;
        }
    }
    #endif
}
#endif

#endif // COLOUR_COMMON_GLSL
