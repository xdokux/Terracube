// ============================================
// SKY & CLOUDS - VERSÃO OTIMIZADA
// ============================================

// CONSTANTES OTIMIZADAS
const float PI = 3.14159265359;
const float TWO_PI = 6.28318530718;

// ============================================
// HASH FUNCTIONS OTIMIZADAS
// ============================================

float hash(vec2 p) {
    // Versão mais rápida com menos operações
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Versão alternativa com melhor distribuição
float hash2(vec2 p) {
    p = fract(p * vec2(443.8975, 397.2973));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

// ============================================
// SKY COLOR - VERSÃO OTIMIZADA
// ============================================

vec3 renderSkyColor(vec3 worldDir, vec3 worldSunVec, float nightFactor) {
    // Pré-calcula valores constantes
    float horizon = max(worldDir.y, 0.0);
    float horizonBlend = pow(horizon, 0.6);
    float sunHeight = worldSunVec.y;
    float sunAngle = max(dot(worldDir, worldSunVec), 0.0);

    // Cores pré-calculadas (evita criar vetores várias vezes)
    vec3 dayZenith = vec3(0.25, 0.5, 0.95);
    vec3 dayHorizon = vec3(0.55, 0.75, 0.95);
    vec3 sunsetZenith = vec3(0.35, 0.2, 0.4);
    vec3 sunsetHorizon = vec3(1.0, 0.45, 0.15);
    vec3 nightZenith = vec3(0.015, 0.015, 0.05);
    vec3 nightHorizon = vec3(0.04, 0.04, 0.08);

    // Gradientes otimizados
    float sunGradient = smoothstep(-0.2, 0.4, sunHeight);
    float sunsetGradient = exp(-abs(sunHeight) * 8.0) * 0.6;

    // Sky mixing otimizado
    vec3 daySky = mix(dayHorizon, dayZenith, horizonBlend);
    vec3 sunsetSky = mix(sunsetHorizon, sunsetZenith, horizonBlend);
    vec3 nightSky = mix(nightHorizon, nightZenith, horizonBlend);

    // Combinação de cores
    vec3 skyColor = mix(nightSky, sunsetSky, sunsetGradient);
    skyColor = mix(skyColor, daySky, sunGradient);
    skyColor = mix(skyColor, nightSky, nightFactor * (1.0 - sunsetGradient));

    // Glow do sol (otimizado)
    float glow = pow(sunAngle, 128.0) * 0.5 * (1.0 - nightFactor);
    skyColor += vec3(1.0, 0.7, 0.3) * glow;

    // Disco solar
    float sunDisk = pow(sunAngle, 2048.0);
    skyColor += vec3(1.0, 0.9, 0.7) * sunDisk * 1.0 * (1.0 - nightFactor);

    // Estrelas otimizadas
    float starVisibility = nightFactor * (1.0 - horizonBlend) * (1.0 - smoothstep(0.0, 0.3, abs(worldDir.y)));
    if (starVisibility > 0.01) {
        // Otimização: reduz resolução das estrelas para performance
        vec2 starUV = worldDir.xz / max(abs(worldDir.y), 0.001) * 50.0; // Menos denso
        vec2 cell = floor(starUV);
        float star = hash(cell);
        float starBright = step(0.997, star) * starVisibility;
        skyColor += starBright * 0.6;
    }

    return skyColor;
}

// ============================================
// RENDER CLOUDS - VERSÃO OTIMIZADA
// ============================================

void renderClouds(inout vec3 skyColor, vec3 worldDir, vec3 cameraPos, vec3 worldSunVec, float nightFactor, float time) {
    if (CLOUD_STEPS < 1) return;

    // Otimização: Early exit se olhando para baixo
    if (worldDir.y < -0.1 && cameraPos.y > CLOUD_HEIGHT_MAX) return;

    float cloudBottom = CLOUD_HEIGHT_MIN;
    float cloudTop = CLOUD_HEIGHT_MAX;

    // Cálculo de interseção otimizado
    float denom = worldDir.y;
    if (abs(denom) < 0.001) return;

    float tNear = (cloudBottom - cameraPos.y) / denom;
    float tFar = (cloudTop - cameraPos.y) / denom;
    if (tNear > tFar) { float tmp = tNear; tNear = tFar; tFar = tmp; }

    float tStart = max(tNear, 0.0);
    float tEnd = min(tFar, 400.0); // Reduzido para performance
    if (tStart >= tEnd) return;

    // Pré-calcula constantes
    float stepSize = (tEnd - tStart) / float(CLOUD_STEPS);
    vec3 sunDir = worldSunVec;
    vec3 sunColor = mix(vec3(0.5, 0.41, 0.25), vec3(0.15, 0.22, 0.32), nightFactor);

    // Pré-calcula wind uma vez
    vec2 wind = vec2(time * 0.001, time * 0.0005);
    vec2 wind2 = wind * 2.0;

    float totalDensity = 0.0;
    vec3 cloudColor = vec3(0.0);
    float cloudHeightRange = cloudTop - cloudBottom;

    // Otimização: reduz samples para nuvens distantes
    int actualSteps = CLOUD_STEPS;
    float distToCloud = tStart;
    if (distToCloud > 100.0) {
        actualSteps = max(CLOUD_STEPS / 2, 4); // Reduz samples longe
        stepSize = (tEnd - tStart) / float(actualSteps);
    }

    for (int i = 0; i < 64; i++) {
        if (i >= actualSteps) break;

        float t = tStart + (float(i) + 0.5) * stepSize;
        vec3 pos = cameraPos + worldDir * t;

        // Altura da nuvem (otimizado)
        float heightFrac = (pos.y - cloudBottom) / cloudHeightRange;
        heightFrac = clamp(heightFrac, 0.0, 1.0);
        float vertDensity = 1.0 - abs(heightFrac - 0.5) * 2.0;
        vertDensity = smoothstep(0.0, 1.0, vertDensity);

        // Amostragem de textura otimizada
        vec2 uv = pos.xz * 0.00012 + wind;
        float base = texture(noisetex, uv).r;
        base = smoothstep(0.2, 0.7, base);

        // Detail (opcional - pode remover para performance)
        #ifdef CLOUD_DETAIL
        vec2 uv2 = pos.xz * 0.00035 + wind2;
        float detail = texture(noisetex, uv2).r;
        detail = smoothstep(0.2, 0.6, detail);
        float noise = mix(base, detail, 0.25);
        #else
        float noise = base;
        #endif

        float density = max(0.0, noise - (1.0 - CLOUD_COVERAGE)) * vertDensity * CLOUD_DENSITY;

        if (density > 0.001) {
            totalDensity += density * stepSize;
            float transmittance = exp(-totalDensity * CLOUD_ABSORPTION);

            // Forward scatter otimizado
            float forwardScatter = 0.3;
            vec3 lightEnergy = sunColor * forwardScatter * density * stepSize * transmittance;
            cloudColor += lightEnergy;
        }
    }

    float transmittance = exp(-totalDensity * CLOUD_ABSORPTION);
    skyColor = skyColor * transmittance + cloudColor;
}

// ============================================
// FUNÇÃO PRINCIPAL OTIMIZADA
// ============================================

vec3 renderSkyWithClouds(vec3 viewPos, vec3 cameraPos, vec3 worldSunVec, float nightFactor, float time) {
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * normalize(viewPos));
    vec3 skyColor = renderSkyColor(worldDir, worldSunVec, nightFactor);
    renderClouds(skyColor, worldDir, cameraPos, worldSunVec, nightFactor, time);
    return skyColor;
}

// ============================================
// FUNÇÃO COM EARLY EXIT PARA PERFORMANCE EXTREMA
// ============================================

vec3 renderSkyWithCloudsFast(vec3 viewPos, vec3 cameraPos, vec3 worldSunVec, float nightFactor, float time) {
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * normalize(viewPos));

    // Early exit: Se estiver olhando para baixo e nuvens acima
    if (worldDir.y < -0.3 && cameraPos.y > CLOUD_HEIGHT_MAX + 20.0) {
        return renderSkyColor(worldDir, worldSunVec, nightFactor);
    }

    vec3 skyColor = renderSkyColor(worldDir, worldSunVec, nightFactor);
    renderClouds(skyColor, worldDir, cameraPos, worldSunVec, nightFactor, time);
    return skyColor;
}

// ============================================
// FUNÇÃO COM CÉU DINÂMICO (MODO NOTURNO MELHORADO)
// ============================================

vec3 renderSkyColorDynamic(vec3 worldDir, vec3 worldSunVec, float nightFactor, float time) {
    vec3 skyColor = renderSkyColor(worldDir, worldSunVec, nightFactor);

    // Aurora boreal (opcional - só à noite)
    #ifdef AURORA
    if (nightFactor > 0.5) {
        float auroraStrength = nightFactor * 0.2;
        vec2 auroraUV = worldDir.xz * 0.5 + vec2(time * 0.01, 0.0);
        float aurora = texture(noisetex, auroraUV).r;
        aurora = smoothstep(0.3, 0.8, aurora) * (1.0 - abs(worldDir.y));
        skyColor += vec3(0.1, 0.5, 0.8) * aurora * auroraStrength;
    }
    #endif

    return skyColor;
}
