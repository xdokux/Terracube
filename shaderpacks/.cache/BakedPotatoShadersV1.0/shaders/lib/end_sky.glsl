#ifndef CINDERLIGHT_END_SKY_GLSL
#define CINDERLIGHT_END_SKY_GLSL

#include "/lib/math.glsl"
#include "/lib/end_common.glsl"

uniform float frameTimeCounter;

vec3 getEndStarLayer(vec2 skyUv, float scale, float threshold,
                     float radius, float seed, float speed) {
    vec2 grid = skyUv * scale;
    vec2 cell = floor(grid);
    vec2 local = fract(grid);
    float randomValue = endHash12(cell + seed);
    if (randomValue < threshold) return vec3(0.0);
    vec2 center = vec2(endHash12(cell + seed + 11.7),
                       endHash12(cell + seed + 37.1));
    float point = 1.0 - smoothstep(radius, radius * 2.45, length(local - center));
    float presence = 1.0;
    float twinkle = 0.88 + 0.12 * sin(frameTimeCounter * speed + randomValue * TAU);
    float temperature = endHash12(cell + seed + 73.4);
    vec3 starColor = mix(vec3(0.64, 0.72, 1.00), vec3(1.00, 0.93, 0.82), temperature);
    float energy = mix(0.58, 1.32, endHash12(cell + seed + 19.3));
    return starColor * point * presence * twinkle * energy;
}

vec3 getEndGalaxyLayer(vec2 skyUv) {
    vec2 grid = skyUv * vec2(31.0, 23.0);
    vec2 cell = floor(grid);
    vec2 local = fract(grid);
    float randomValue = endHash12(cell + 121.7);
    if (randomValue < 0.9915) return vec3(0.0);
    vec2 center = vec2(endHash12(cell + 8.2), endHash12(cell + 41.9));
    vec2 delta = local - center;
    float angle = endHash12(cell + 67.3) * TAU;
    float cosineAngle = cos(angle);
    float sineAngle = sin(angle);
    vec2 rotated = vec2(delta.x * cosineAngle - delta.y * sineAngle,
                        delta.x * sineAngle + delta.y * cosineAngle);
    rotated *= vec2(0.66, 3.6);
    float radius = length(rotated);
    float body = 1.0 - smoothstep(0.035, 0.185, radius);
    float core = 1.0 - smoothstep(0.008, 0.055, radius);
    float presence = 1.0;
    vec3 galaxyColor = mix(vec3(0.055, 0.080, 0.190), vec3(0.145, 0.060, 0.220),
                           endHash12(cell + 92.5));
    return galaxyColor * (body * 0.34 + core * 0.42) * presence;
}

vec3 getEndNebulaPalette(float phase) {
    vec3 indigoGas = vec3(0.014, 0.007, 0.040);
    vec3 violetGas = vec3(0.052, 0.014, 0.096);
    vec3 blueGas = vec3(0.008, 0.040, 0.108);
    vec3 magentaGas = vec3(0.062, 0.012, 0.072);

    float palettePosition = fract(phase) * 5.0;
    float segment = floor(palettePosition);
    float blendAmount = smoothCubic(fract(palettePosition));

    if (segment < 1.0) return mix(indigoGas, violetGas, blendAmount);
    if (segment < 2.0) return mix(violetGas, magentaGas, blendAmount);
    if (segment < 3.0) return mix(magentaGas, blueGas, blendAmount);
    if (segment < 4.0) return mix(blueGas, violetGas, blendAmount);
    return mix(violetGas, indigoGas, blendAmount);
}

vec3 getEndNebulae(vec3 direction) {
    float drift = frameTimeCounter * 0.00008;

    // Anisotropic low-frequency coordinates create enormous stretched gas systems
    // instead of circular patches while retaining seamless direction-space mapping.
    vec3 nebulaPosition = direction * vec3(2.05, 1.35, 2.55) +
                          vec3(drift, -drift * 0.63, drift * 0.41);
    float noise0 = endValueNoise3D(nebulaPosition);

    float warpX = sin(dot(nebulaPosition, vec3(1.37, -1.91, 1.63)) + noise0 * 2.7);
    float warpY = sin(dot(nebulaPosition, vec3(-1.71, 1.29, 2.13)) - noise0 * 2.2);
    float warpZ = sin(dot(nebulaPosition, vec3(2.03, 1.57, -1.41)) + noise0 * 1.9);
    vec3 warpedPosition = nebulaPosition.yzx * 2.03 +
                          vec3(warpX, warpY, warpZ) * 0.18 +
                          vec3(17.1, -9.7, 12.3);
    float noise1 = endValueNoise3D(warpedPosition);

    // Broad flowing sheets form the connected supernova-remnant silhouette.
    float sheetA = sin(dot(direction, vec3(2.55, -1.65, 2.10)) +
                       noise0 * 3.2 + noise1 * 1.6) * 0.5 + 0.5;
    float sheetB = sin(dot(direction, vec3(-2.85, 2.15, 1.25)) -
                       noise0 * 1.8 + noise1 * 3.4) * 0.5 + 0.5;

    float broadField = noise0 * 0.48 + noise1 * 0.25 +
                       sheetA * 0.17 + sheetB * 0.10;
    float broadCloud = smoothstep(0.39, 0.63, broadField);

    float bridgeField = (1.0 - abs(noise0 - noise1)) * 0.44 +
                        noise0 * 0.25 + sheetB * 0.18 + sheetA * 0.13;
    float gasBridge = smoothstep(0.57, 0.81, bridgeField) * 0.42;
    float baseCoverage = 1.0 - (1.0 - broadCloud) * (1.0 - gasBridge);

    // This exact early-out avoids all fine-detail work in the preserved black voids.
    if (baseCoverage <= 0.0) return vec3(0.0);

    // A third warped scale supplies fine cloud texture only where gas is present.
    vec3 detailPosition = warpedPosition.zxy * 2.08 +
                          vec3(noise1 - 0.5, noise0 - 0.5, noise0 - noise1) * 0.48 +
                          vec3(-7.3, 12.8, 5.9);
    float noise2 = sin(dot(detailPosition, vec3(1.27, 2.17, -1.83)) +
                       sin(dot(detailPosition, vec3(-2.63, 1.51, 2.89))) * 0.79) *
                   0.5 + 0.5;
    float detail3 = sin(dot(detailPosition, vec3(1.83, -2.59, 3.31)) +
                        sin(dot(detailPosition, vec3(-3.07, 4.21, 1.69))) * 0.73) *
                    0.5 + 0.5;
    float detail4 = sin(dot(detailPosition, vec3(-4.91, 6.13, 4.57)) +
                        sin(dot(detailPosition, vec3(7.19, 2.71, -6.41))) * 0.53) *
                    0.5 + 0.5;

    float smoothFbm = noise0 * 0.49 + noise1 * 0.27 + noise2 * 0.15 +
                      detail3 * 0.06 + detail4 * 0.03;
    float ridgedFbm = (1.0 - abs(noise0 * 2.0 - 1.0)) * 0.40 +
                      (1.0 - abs(noise1 * 2.0 - 1.0)) * 0.25 +
                      (1.0 - abs(noise2 * 2.0 - 1.0)) * 0.20 +
                      (1.0 - abs(detail3 * 2.0 - 1.0)) * 0.10 +
                      (1.0 - abs(detail4 * 2.0 - 1.0)) * 0.05;

    // Equality ridges create broken plasma filaments rather than repeated contour rings.
    float filamentField = 1.0 - abs((noise2 * 0.52 + detail3 * 0.48) -
                                    (detail4 * 0.57 + noise1 * 0.43));
    float filaments = smoothstep(0.82, 0.965, filamentField) *
                      smoothstep(0.20, 0.68, baseCoverage);
    float wisps = smoothstep(0.60, 0.88, ridgedFbm * 0.70 + detail3 * 0.30);
    float denseCores = smoothstep(0.55, 0.82,
                                  smoothFbm * 0.62 + noise2 * 0.23 + detail4 * 0.15);

    float pocketField = 1.0 - abs((detail3 * 0.60 + detail4 * 0.40) * 2.0 - 1.0);
    float darkPockets = smoothstep(0.78, 0.95, pocketField) *
                        smoothstep(0.30, 0.80, baseCoverage);

    float nebulaDensity = baseCoverage *
                          (0.46 + smoothFbm * 0.26 + wisps * 0.15 +
                           filaments * 0.12 + denseCores * 0.12);
    nebulaDensity *= 1.0 - darkPockets * 0.19;
    nebulaDensity = saturate(nebulaDensity);
    nebulaDensity *= smoothstep(0.012, 0.14, nebulaDensity);

    // One continuous cyclic colour field flows through every connected gas layer.
    float colorPhase = fract(dot(direction, vec3(0.57, -0.30, 0.76)) * 0.54 +
                             noise0 * 0.15 + noise1 * 0.10 + 0.18);
    vec3 nebulaColor0 = getEndNebulaPalette(colorPhase);
    vec3 nebulaColor1 = getEndNebulaPalette(
        fract(colorPhase + (noise2 - 0.5) * 0.10 + sheetB * 0.04));
    vec3 nebulaColor = mix(nebulaColor0, nebulaColor1, 0.32);

    float emission = 0.18 + smoothFbm * 0.17 + denseCores * 0.11 + wisps * 0.06;
    vec3 nebula = nebulaColor * nebulaDensity * emission;

    vec3 blueGas = vec3(0.008, 0.040, 0.108);
    vec3 violetGas = vec3(0.052, 0.014, 0.096);
    vec3 cyanGas = vec3(0.010, 0.073, 0.108);
    nebula += mix(blueGas, violetGas, 0.42) * wisps * nebulaDensity * 0.038;
    nebula += cyanGas * filaments * nebulaDensity * 0.026;

    return nebula;
}

vec3 getEndDeepSpaceBackground(vec3 direction) {
    direction = safeNormalize(direction);
    vec2 skyUv = endOctahedralMap(direction);
    float horizonDepth = 1.0 - smoothstep(0.18, 0.92, abs(direction.y));

    vec3 sky = mix(vec3(0.0010, 0.0013, 0.0030),
                   vec3(0.0038, 0.0018, 0.0085), horizonDepth * 0.72);
    sky += getEndNebulae(direction);
    sky += getEndGalaxyLayer(skyUv);
    sky += getEndStarLayer(skyUv, 182.0, 0.9760, 0.045, 3.1, 0.32);
    sky += getEndStarLayer(skyUv, 331.0, 0.9870, 0.035, 47.9, 0.47);
    sky += getEndStarLayer(skyUv, 579.0, 0.9950, 0.028, 103.4, 0.61);
    return sky;
}

vec3 getEndSpaceSky(vec3 direction) {
    return getEndDeepSpaceBackground(direction);
}

#endif
