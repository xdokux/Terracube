// ============================================
// blocklight_shadow.glsl - Sombras para luzes de bloco
// ============================================

#ifndef BLOCKLIGHT_SHADOW_GLSL
#define BLOCKLIGHT_SHADOW_GLSL

// ============================================
// CONFIGURAÇÕES
// ============================================
#define MAX_BLOCKLIGHTS 64

// ============================================
// ESTRUTURA PARA LUZES DE BLOCO
// ============================================
struct BlockLight {
    vec3 position;
    float radius;
    vec3 color;
    float intensity;
};

// ============================================
// BUFFER DE LUZES (binding 3)
// ============================================
layout(std430, binding = 3) coherent buffer blockLightsBuffer {
    uint lightCount;
    BlockLight lights[MAX_BLOCKLIGHTS];
} blockLights;

// ============================================
// FUNÇÃO PARA REGISTRAR LUZ
// ============================================
void registerBlockLight(vec3 position, float radius, vec3 color, float intensity) {
    uint index = atomicAdd(blockLights.lightCount, 1u);
    if (index < MAX_BLOCKLIGHTS) {
        blockLights.lights[index].position = position;
        blockLights.lights[index].radius = radius;
        blockLights.lights[index].color = color;
        blockLights.lights[index].intensity = intensity;
    }
}

// ============================================
// FUNÇÕES DE SOMBRA (apenas para fragment/composite shaders)
// ============================================
#ifndef COMPUTE_SHADER

// ============================================
// FUNÇÃO DE SOMBRA PARA LUZ DE BLOCO (ray marching)
// ============================================
float getBlockLightShadow(vec3 worldPos, vec3 lightPos, float radius, vec3 normal) {
    vec3 toLight = lightPos - worldPos;
    float dist = length(toLight);

    if (dist > radius) return 0.0;

    vec3 lightDir = toLight / dist;

    float NdotL = dot(normal, lightDir);
    if (NdotL <= 0.0) return 0.0;

    float shadow = 1.0;
    float stepSize = max(0.3, dist / 24.0);
    vec3 currentPos = worldPos;

    for (float t = stepSize; t < dist; t += stepSize) {
        currentPos += lightDir * stepSize;

        vec4 viewPos_current = gbufferModelView * vec4(currentPos, 1.0);
        vec4 clipPos = gbufferProjection * viewPos_current;
        vec3 ndcPos = clipPos.xyz / clipPos.w;
        vec2 screenPos = ndcPos.xy * 0.5 + 0.5;

        if (screenPos.x >= 0.0 && screenPos.x <= 1.0 &&
            screenPos.y >= 0.0 && screenPos.y <= 1.0) {
            float depth = texture(depthtex0, screenPos).r;
            if (depth < 1.0) {
                vec3 ndc = vec3(screenPos, depth) * 2.0 - 1.0;
                vec4 viewPos4 = gbufferProjectionInverse * vec4(ndc, 1.0);
                vec3 viewPos = viewPos4.xyz / viewPos4.w;

                if (viewPos.z > viewPos_current.z + 0.01) {
                    shadow = 0.0;
                    break;
                }
            }
        }
    }

    return shadow;
}

// ============================================
// CALCULA ILUMINAÇÃO DE BLOCOS COM SOMBRA
// Retorna em shadowed a luz com oclusão, e em unshadowed a luz máxima (sem sombra)
// ============================================
void calculateBlockLighting(vec3 worldPos, vec3 normal, out vec3 shadowed, out vec3 unshadowed) {
    shadowed = vec3(0.0);
    unshadowed = vec3(0.0);

    uint count = min(blockLights.lightCount, MAX_BLOCKLIGHTS);

    for (uint i = 0u; i < count; i++) {
        BlockLight light = blockLights.lights[i];

        vec3 toLight = light.position - worldPos;
        float dist = length(toLight);

        if (dist > light.radius) continue;

        float atten = 1.0 - (dist / light.radius);
        atten = atten * atten;

        vec3 contrib = light.color * light.intensity * atten;
        unshadowed += contrib;

        float shadow = getBlockLightShadow(worldPos, light.position, light.radius, normal);
        shadowed += contrib * shadow;
    }
}

#endif // COMPUTE_SHADER

#endif // BLOCKLIGHT_SHADOW_GLSL
