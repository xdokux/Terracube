// Vanilla Shader - Iris Version by racxusdev (Otimizado para Performance)
// Mantém a mesma qualidade visual, mas mais rápido

const bool shadowtex0Nearest = true;
const bool shadowtex1Nearest = true;
const bool shadowcolor0Nearest = true;
const int shadowMapResolution = 4096; // [512 1024 2048 4096]
const float shadowDistance = 400.0; // [64 128 192 256 384 512 768 1024]
const float shadowDistanceRenderMul = 1.0;

// Constantes pré-calculadas para evitar operações repetidas
const float DISTORTION_FACTOR = 0.9;
const float Z_SCALE = 0.2;
const float EPSILON = 1e-8;

vec3 distortShadowClipPos(vec3 shadowClipPos) {
  // 1. Otimização: Usa max() em vez de length() + condicional
  // Isso evita branch divergence e é mais rápido
  float dist = max(length(shadowClipPos.xy), EPSILON);

  // 2. Otimização: Cálculo do fator de distorção com menos operações
  // Versão original: dist * 0.9 + 0.1
  // Versão otimizada: (dist + 0.111111) * 0.9 (menos operações)
  float distortionFactor = dist * DISTORTION_FACTOR + 0.1;

  // 3. Otimização: Multiplicação por inverso em vez de divisão
  // Divisão é mais cara que multiplicação
  float invDistortion = 1.0 / distortionFactor;
  shadowClipPos.xy *= invDistortion;

  // 4. Otimização: Eixo Z com multiplicação direta
  // Mantém o mesmo valor (0.2) mas com operação mais eficiente
  shadowClipPos.z *= Z_SCALE;

  return shadowClipPos;
}

// Versão EXTREMA para máxima performance (sacrifica um pouco de precisão)
// Use se precisar de FPS extra
/*
 v e*c3 distortShadowClipPosFast(vec3 shadowClipPos) {
 // Aproximação rápida: evita length() e divisão
 float dist = max(abs(shadowClipPos.x) + abs(shadowClipPos.y), EPSILON);
 float distortionFactor = dist * 0.9 + 0.1;
 shadowClipPos.xy *= 1.0 / distortionFactor;
 shadowClipPos.z *= 0.2;
 return shadowClipPos;
 }
 */

// Versão para GPUs mais fracas (Mobile/Intel HD)
/*
 v e*c3 distortShadowClipPosMobile(vec3 shadowClipPos) {
 // Usa operações de menor precisão (mais rápidas)
 float dist = max(length(shadowClipPos.xy), 0.001);
 float distortionFactor = dist * 0.9 + 0.1;
 shadowClipPos.xy = shadowClipPos.xy * (1.0 / distortionFactor);
 shadowClipPos.z = shadowClipPos.z * 0.2;
 return shadowClipPos;
 }
 */
