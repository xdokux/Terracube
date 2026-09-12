// ============================================================
//  CinematicVanilla V3 - tonemap.glsl
//  Reinhard-Jodie Extended + cinematic film grade.
//  V3 improvements:
//   - Seasonal color presets (Summer/Autumn/Winter/Spring/None)
//   - Poster Mode: aggressive grade for screenshots
//   - Improved split-tone with stronger teal-orange separation
//   - Film halation on bright highlights
// ============================================================

const float oneMinusShoulder         = 1.0 - SHOULDER_STRENGTH;
const float shoulderFactor           = oneMinusShoulder * 3.0;
const float shoulderWhitePointFactor = oneMinusShoulder / (WHITE_POINT * WHITE_POINT);

float getLuminance(in vec3 col){
    return dot(col, vec3(0.2126, 0.7152, 0.0722));
}

vec3 saturation(in vec3 col, in float a){
    float luma = getLuminance(col);
    return (col - luma) * a + luma;
}

vec3 contrast(in vec3 col, in float a){
    return (col - 0.5) * a + 0.5;
}

// Reinhard Extended Luminance
vec3 modifiedReinhardExtended(in vec3 color){
    float s = sumOf(color);
    return color * ((3.0 + s * shoulderWhitePointFactor) / (shoulderFactor + s));
}

// Reinhard Jodie Extended (per-channel + luminance blend)
vec3 modifiedReinhardJodieExtended(in vec3 color){
    float s = sumOf(color);
    vec3 rC = color * ((1.0 + color * shoulderWhitePointFactor) / (oneMinusShoulder + color));
    vec3 rL = color * ((3.0 + s * shoulderWhitePointFactor) / (shoulderFactor + s));
    return (rC - rL) * rC + rL;
}

// ─── Seasonal Grade ──────────────────────────────────────────────────────────
// Returns an additive tint + saturation multiplier for each season.
// SEASONAL_PRESET: 0=None 1=Summer 2=Autumn 3=Winter 4=Spring
vec3 seasonalGrade(in vec3 col){
    float luma = getLuminance(col);

    #if SEASONAL_PRESET == 1
        // Summer — warm golden, high contrast, lush greens
        col *= vec3(1.025, 1.010, 0.975);
        col  = saturation(col, 1.10);
        col  = contrast(col, 1.06);

    #elif SEASONAL_PRESET == 2
        // Autumn — amber shadows, desaturated sky, warm overall
        float shadowW = saturate(1.0 - luma * 2.5);
        col += vec3(0.030,  0.012, -0.018) * shadowW;   // amber shadow push
        col *= vec3(1.030, 1.012, 0.970);                // warm temp shift
        col  = saturation(col, 0.92);

    #elif SEASONAL_PRESET == 3
        // Winter — cold blue-white, desaturated, faint cyan shadows
        float shadowW = saturate(1.0 - luma * 2.5);
        col += vec3(-0.014, -0.004, 0.024) * shadowW;   // cold shadow push
        col *= vec3(0.975, 0.988, 1.028);                // cool temp shift
        col  = saturation(col, 0.82);
        col  = contrast(col, 1.08);

    #elif SEASONAL_PRESET == 4
        // Spring — soft pastel, bright, lifted shadows, green-pink bias
        col  = max(col, vec3(0.022));                    // lifted blacks
        col *= vec3(0.998, 1.015, 0.990);                // subtle green push
        col  = saturation(col, 0.96);
        col  = contrast(col, 0.97);

    #endif

    return col;
}

// ─── Cinematic Film Grade ────────────────────────────────────────────────────
// Applied in sRGB space after tonemapping. Pure math, zero texture reads.
vec3 cinematicGrade(in vec3 col){
    float luma = getLuminance(col);

    // 1. Shadow lift — prevents pure black, gives film-print look
    col = max(col, vec3(0.018));

    // 2. Split-tone: Shadows=teal-blue, Highlights=warm amber
    float shadowW    = saturate(1.0 - luma * 2.8);
    float highlightW = saturate(luma * 2.0 - 0.60);

    col += vec3(-0.012, -0.004, 0.018) * shadowW;
    col += vec3( 0.018,  0.010, -0.008) * highlightW;

    // 3. Midtone warmth (slight amber temperature)
    col *= vec3(1.015, 1.006, 0.988);

    // 4. Subtle midtone desaturation — analog film character
    float midW = saturate(1.0 - abs(luma * 2.0 - 1.0));
    col = mix(col, saturation(col, 0.88), midW * 0.3);

    // 5. Film halation — bright highlights bleed warm red/orange
    //    Simulates light scattering in film emulsion backing layer
    float halationW = saturate(luma - 0.72) * 2.0;
    col += vec3(0.060, 0.018, 0.006) * halationW * halationW;

    // 6. Seasonal grade on top
    col = seasonalGrade(col);

    return col;
}

// ─── Poster Mode Grade ───────────────────────────────────────────────────────
// Aggressive version of cinematicGrade for POSTER_MODE screenshots.
// Stronger teal-orange, crushed blacks, boosted contrast & saturation.
vec3 posterGrade(in vec3 col){
    float luma = getLuminance(col);

    // Deep shadow crush (cinematic blacks)
    col = pow(col, vec3(1.08));

    // Strong teal-orange split tone
    float shadowW    = saturate(1.0 - luma * 2.2);
    float highlightW = saturate(luma * 1.8 - 0.50);

    col += vec3(-0.022, -0.008, 0.032) * shadowW;
    col += vec3( 0.030,  0.016, -0.018) * highlightW;

    // Warm temperature push
    col *= vec3(1.022, 1.010, 0.976);

    // Film halation — stronger in poster mode
    float halationW = saturate(luma - 0.68) * 2.5;
    col += vec3(0.090, 0.028, 0.008) * halationW * halationW;

    // Boost contrast and saturation for that "epic screenshot" look
    col = contrast(col, 1.14);
    col = saturation(col, 1.18);

    // Seasonal grade still applies in poster mode
    col = seasonalGrade(col);

    return col;
}
