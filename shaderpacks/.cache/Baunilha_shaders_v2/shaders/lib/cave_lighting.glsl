// ============================================
// CAVERNAS - EFEITO EXPONENCIAL (VERSÃO ULTRA RÁPIDA)
// ============================================
// NOVAS CONFIGS (apenas as que não existem)
const float CAVE_MIN_LIGHT = 0.02; // [0.0 0.1]
const float CAVE_MAX_LIGHT = 0.18; // [0.05 0.5]
const float CAVE_EXPONENT = 2.5; // [0.5 5.0]
const float CAVE_DARKNESS = 0.15; // [0.0 0.5]

const float NIGHT_CAVE_MIN_LIGHT = 0.01; // [0.0 0.1]
const float NIGHT_CAVE_MAX_LIGHT = 0.25; // [0.05 0.5]
const float NIGHT_CAVE_EXPONENT = 2.0; // [0.5 5.0]
const float NIGHT_CAVE_DARKNESS = 0.25; // [0.0 0.5]

// ============================================
// FUNÇÕES OTIMIZADAS (MÁXIMA PERFORMANCE)
// ============================================

// VERSÃO 1: ULTRA RÁPIDA (sem exp() e sem clamp)
float caveFactorExponentialFast(float skylight) {
	// Calcula t sem clamp (economiza 1 operação)
	float t = (skylight - CAVE_MIN_LIGHT) / (CAVE_MAX_LIGHT - CAVE_MIN_LIGHT);

	// Aproximação de exp() usando série de Taylor (mais rápida que exp())
	// exp(-x) ≈ 1 - x + x²/2 - x³/6 para x pequeno
	float x = t * CAVE_EXPONENT;
	float expApprox = 1.0 - x + x * x * 0.5 - x * x * x * 0.166666;

	// Inverte e aplica strength em uma única operação
	float rawFactor = 1.0 - clamp(expApprox, 0.0, 1.0);

	// Aplica CAVE_STRENGTH (que já existe) e CAVE_DARKNESS
	return mix(CAVE_DARKNESS, 1.0, rawFactor * CAVE_STRENGTH + (1.0 - CAVE_STRENGTH));
}

// VERSÃO 2: MAIS RÁPIDA AINDA (sem exp(), sem smoothstep)
float caveFactorExponentialUltra(float skylight) {
	// Otimização: t pré-calculado com multiplicação única
	float t = (skylight - 0.02) * 6.25; // 1/(0.18-0.02) = 6.25

	// Aproximação polinomial (ainda mais rápida)
	// Usa apenas multiplicações e adições
	float x = t * CAVE_EXPONENT;
	float rawFactor = 1.0 - x + x * x * 0.5;
	rawFactor = clamp(rawFactor, 0.0, 1.0);

	// Aplica intensidade
	return CAVE_DARKNESS + (1.0 - CAVE_DARKNESS) * (rawFactor * CAVE_STRENGTH + (1.0 - CAVE_STRENGTH));
}

// VERSÃO 3: COM LOOKUP TABLE (MAIS RÁPIDA PARA MUITAS CHAMADAS)
float caveFactorExponentialLUT(float skylight) {
	// Índice da tabela (0-31) baseado na luz
	float index = floor((skylight - 0.02) * 312.5); // 31/(0.18-0.02) = 193.75
	index = clamp(index, 0.0, 31.0);

	// Tabela pré-calculada (valores exponenciais)
	// Você pode pré-calcular isso e colocar como constante
	const float LUT[32] = float[32](
		0.02, 0.03, 0.04, 0.06, 0.08, 0.11, 0.15, 0.20,
		0.26, 0.33, 0.41, 0.50, 0.59, 0.68, 0.76, 0.83,
		0.89, 0.93, 0.96, 0.98, 0.99, 0.99, 1.00, 1.00,
		1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00
	);

	int idx = int(index);
	return mix(LUT[idx], LUT[idx+1], fract(index));
}

// VERSÃO 4: NOTURNO ULTRA RÁPIDO
float caveFactorExponentialNightFast(float skylight) {
	float t = (skylight - NIGHT_CAVE_MIN_LIGHT) / (NIGHT_CAVE_MAX_LIGHT - NIGHT_CAVE_MIN_LIGHT);

	float x = t * NIGHT_CAVE_EXPONENT;
	float expApprox = 1.0 - x + x * x * 0.5 - x * x * x * 0.166666;

	float rawFactor = 1.0 - clamp(expApprox, 0.0, 1.0);
	return mix(NIGHT_CAVE_DARKNESS, 1.0, rawFactor * NIGHT_CAVE_STRENGTH + (1.0 - NIGHT_CAVE_STRENGTH));
}

// VERSÃO 5: COMPLETA OTIMIZADA (com dia/noite integrado)
float caveFactorExponentialCompleteFast(float skylight, float blockLight, float isNight) {
	// Seleção rápida de parâmetros (sem if)
	float minLight = mix(CAVE_MIN_LIGHT, NIGHT_CAVE_MIN_LIGHT, isNight);
	float maxLight = mix(CAVE_MAX_LIGHT, NIGHT_CAVE_MAX_LIGHT, isNight);
	float exponent = mix(CAVE_EXPONENT, NIGHT_CAVE_EXPONENT, isNight);
	float strength = mix(CAVE_STRENGTH, NIGHT_CAVE_STRENGTH, isNight);
	float darkness = mix(CAVE_DARKNESS, NIGHT_CAVE_DARKNESS, isNight);

	// Ajuste da luz de bloco (otimizado)
	float lightAdjust = blockLight * 0.05;
	minLight += lightAdjust;
	maxLight += lightAdjust * 0.5;

	// Cálculo rápido
	float t = (skylight - minLight) / (maxLight - minLight);
	float x = t * exponent;
	float expApprox = 1.0 - x + x * x * 0.5 - x * x * x * 0.166666;
	float rawFactor = 1.0 - clamp(expApprox, 0.0, 1.0);

	return mix(darkness, 1.0, rawFactor * strength + (1.0 - strength));
}

// VERSÃO 6: COM EARLY EXIT (economiza quando já está claro)
float caveFactorExponentialEarly(float skylight) {
	// Se estiver claro, sai rápido
	if (skylight > CAVE_MAX_LIGHT) return 1.0;
	if (skylight < CAVE_MIN_LIGHT) return CAVE_DARKNESS;

	// Só calcula se estiver na região de transição
	float t = (skylight - CAVE_MIN_LIGHT) / (CAVE_MAX_LIGHT - CAVE_MIN_LIGHT);
	float x = t * CAVE_EXPONENT;
	float expApprox = 1.0 - x + x * x * 0.5;
	float rawFactor = 1.0 - clamp(expApprox, 0.0, 1.0);

	return mix(CAVE_DARKNESS, 1.0, rawFactor * CAVE_STRENGTH + (1.0 - CAVE_STRENGTH));
}

// ============================================
// FUNÇÃO RECOMENDADA (MELHOR CUSTO-BENEFÍCIO)
// ============================================

// Use esta função no seu shader principal
float caveFactor(float skylight) {
	// Versão ultra rápida com early exit
	if (skylight > CAVE_MAX_LIGHT) return 1.0;
	if (skylight < CAVE_MIN_LIGHT) return CAVE_DARKNESS;

	float t = (skylight - CAVE_MIN_LIGHT) * 6.25; // 1/(CAVE_MAX_LIGHT - CAVE_MIN_LIGHT)
	float x = t * CAVE_EXPONENT;
	float rawFactor = 1.0 - x + x * x * 0.5;
	rawFactor = clamp(rawFactor, 0.0, 1.0);

	return CAVE_DARKNESS + (1.0 - CAVE_DARKNESS) * (rawFactor * CAVE_STRENGTH + (1.0 - CAVE_STRENGTH));
}
