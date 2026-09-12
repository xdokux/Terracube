// Vogel disk sampling + Interleaved Gradient Noise for soft shadows
// Replaces grid-based PCF with better distributed samples
// VERSÃO COM BIAS DINÂMICO

// REMOVIDAS as declarações de SHADOW_RADIUS e SHADOW_RANGE
// Elas já existem em outro lugar do shader

const float GOLDEN_ANGLE = 2.399963229728653; // PI * (3.0 - sqrt(5.0))
const float PI_2 = 6.283185307179586;
const float SHADOW_BIAS_BASE = 0.0015;
const float SHADOW_BIAS_DISTANCE_FACTOR = 0.001; // Aumenta bias com distância

// Noise interleaved otimizado
float interleavedGradientNoise(vec2 coord) {
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(coord, magic.xy)));
}

// Vogel Disk sampling
vec2 vogelDisk(uint sampleIndex, float rMultiplier, float offsetAngle) {
    float r = sqrt(float(sampleIndex) + 0.5) * rMultiplier;
    float theta = float(sampleIndex) * GOLDEN_ANGLE + offsetAngle;
    return vec2(cos(theta), sin(theta)) * r;
}

// Função principal com BIAS DINÂMICO
vec3 getSoftShadow(vec4 shadowClipPos, float nightFactor, vec2 coord) {
    // Calcula coordenadas de pixel e ângulo de offset
    vec2 screenPixelCoord = coord * vec2(viewWidth, viewHeight);
    float offsetAngle = interleavedGradientNoise(screenPixelCoord) * PI_2;

    // Usa SHADOW_RANGE e SHADOW_RADIUS que já existem
    int samples = SHADOW_RANGE * SHADOW_RANGE * 4;

    // Multiplicador de raio (inverso da raiz quadrada)
    float rMultiplier = 1.0 / sqrt(float(samples));

    // Tamanho do texel baseado no raio da sombra
    float texelSize = SHADOW_RADIUS / shadowMapResolution;

    // Pré-calcula o W para otimização
    float clipW = shadowClipPos.w;

    // CALCULA BIAS DINÂMICO BASEADO NA DISTÂNCIA
    float distanceToCamera = length(shadowClipPos.xyz);
    float dynamicBias = SHADOW_BIAS_BASE * (1.0 + distanceToCamera * SHADOW_BIAS_DISTANCE_FACTOR);

    // LIMITA O BIAS PARA EVITAR OVERFLOW
    dynamicBias = min(dynamicBias, 0.01);

    vec3 shadowAccum = vec3(0.0);

    // Loop com número fixo máximo para evitar problemas de compilação
    for (int i = 0; i < 64; i++) {
        if (i >= samples) break;

        // Calcula offset do disco de Vogel
        vec2 offset = vogelDisk(uint(i), rMultiplier, offsetAngle) * texelSize;

        // Aplica offset e bias dinâmico
        vec4 offsetShadowClipPos = shadowClipPos;
        offsetShadowClipPos.xy += offset * clipW;
        offsetShadowClipPos.z -= dynamicBias; // BIAS DINÂMICO

        // Converte para NDC (Normalized Device Coordinates)
        vec3 shadowNDCPos = offsetShadowClipPos.xyz / offsetShadowClipPos.w;

        // Aplica distorção do shadow map
        shadowNDCPos = distortShadowClipPos(shadowNDCPos);

        // Converte para coordenadas de tela (0-1)
        vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;

        // Acumula o resultado da sombra
        shadowAccum += getShadow(shadowScreenPos);
    }

    // Retorna a média das amostras
    return shadowAccum / float(samples);
}

// VERSÃO COM BIAS DINÂMICO E EARLY EXIT (otimizada)
/*
 v e*c3 getSoftShadowOptimized(vec4 shadowClipPos, float nightFactor, vec2 coord) {
 vec2 screenPixelCoord = coord * vec2(viewWidth, viewHeight);
 float offsetAngle = interleavedGradientNoise(screenPixelCoord) * PI_2;

 int samples = SHADOW_RANGE * SHADOW_RANGE * 4;
 float rMultiplier = 1.0 / sqrt(float(samples));
 float texelSize = SHADOW_RADIUS / shadowMapResolution;
 float clipW = shadowClipPos.w;

 // Bias dinâmico com curva mais suave
 float distanceToCamera = length(shadowClipPos.xyz);
 float normalizedDist = min(distanceToCamera / shadowDistance, 1.0);
 float dynamicBias = SHADOW_BIAS_BASE * (1.0 + normalizedDist * normalizedDist * 0.005);
 dynamicBias = min(dynamicBias, 0.01);

 vec3 shadowAccum = vec3(0.0);
 int samplesTaken = 0;

 for (int i = 0; i < 64; i++) {
     if (i >= samples) break;

     vec2 offset = vogelDisk(uint(i), rMultiplier, offsetAngle) * texelSize;

     vec4 offsetShadowClipPos = shadowClipPos;
     offsetShadowClipPos.xy += offset * clipW;
     offsetShadowClipPos.z -= dynamicBias;

     vec3 shadowNDCPos = offsetShadowClipPos.xyz / offsetShadowClipPos.w;
     shadowNDCPos = distortShadowClipPos(shadowNDCPos);
     vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;

     float shadowValue = getShadow(shadowScreenPos);
     shadowAccum += shadowValue;
     samplesTaken++;

     // EARLY EXIT: Se já estiver muito escuro, não precisa continuar
     if (samplesTaken > 8 && shadowAccum.r < 0.1 && shadowAccum.g < 0.1 && shadowAccum.b < 0.1) {
         break;
         }
         }

         return shadowAccum / float(samplesTaken);
         }
         */

// VERSÃO COM BIAS DINÂMICO E QUALIDADE ADAPTATIVA
/*
 v e*c3 getSoftShadowAdaptive(vec4 shadowClipPos, float nightFactor, vec2 coord) {
 vec2 screenPixelCoord = coord * vec2(viewWidth, viewHeight);
 float offsetAngle = interleavedGradientNoise(screenPixelCoord) * PI_2;

 // ADAPTATIVO: Menos samples para objetos distantes
 float distanceToCamera = length(shadowClipPos.xyz);
 float qualityFactor = 1.0 - min(distanceToCamera / shadowDistance, 1.0);
 int adaptiveSamples = int(mix(16.0, float(SHADOW_RANGE * SHADOW_RANGE * 4), qualityFactor));
 adaptiveSamples = max(adaptiveSamples, 8); // Mínimo 8 samples

 float rMultiplier = 1.0 / sqrt(float(adaptiveSamples));
 float texelSize = SHADOW_RADIUS / shadowMapResolution;
 float clipW = shadowClipPos.w;

 // Bias dinâmico adaptativo
 float normalizedDist = min(distanceToCamera / shadowDistance, 1.0);
 float dynamicBias = SHADOW_BIAS_BASE * (1.0 + normalizedDist * 0.003);
 dynamicBias = min(dynamicBias, 0.008);

 vec3 shadowAccum = vec3(0.0);

 for (int i = 0; i < 64; i++) {
     if (i >= adaptiveSamples) break;

     vec2 offset = vogelDisk(uint(i), rMultiplier, offsetAngle) * texelSize;

     vec4 offsetShadowClipPos = shadowClipPos;
     offsetShadowClipPos.xy += offset * clipW;
     offsetShadowClipPos.z -= dynamicBias;

     vec3 shadowNDCPos = offsetShadowClipPos.xyz / offsetShadowClipPos.w;
     shadowNDCPos = distortShadowClipPos(shadowNDCPos);
     vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;
     shadowAccum += getShadow(shadowScreenPos);
     }

     return shadowAccum / float(adaptiveSamples);
     }
     */
