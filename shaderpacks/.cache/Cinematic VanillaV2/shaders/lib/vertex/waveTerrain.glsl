// ============================================================
//  CinematicVanilla V2 - waveTerrain.glsl
//  Wind animation: simple → gusting based on WIND_QUALITY.
//  Supports grass, leaves, double-tall plants, hanging foliage.
// ============================================================

#if WIND_QUALITY == 0
// No wind at all (LOW preset)
vec3 getTerrainWave(in vec3 vPos, in vec2 wXZ, in float midY, in float id, in float outside, in float t){
    return vPos;
}

#elif WIND_QUALITY == 1
// Simple sinusoidal wind (MEDIUM preset — matches V1 behaviour + clean)
vec3 getTerrainWave(in vec3 vPos, in vec2 wXZ, in float midY, in float id, in float outside, in float t){
    if(WIND_SPEED <= 0.0) return vPos;

    float windStr = sin(-sumOf(id == 10801 ? floor(wXZ) : wXZ) * WIND_FREQUENCY
                      + t * WIND_SPEED) * outside;

    // Simple foliage (id 10000–10099): horizontal sway
    if(id >= 10000.0 && id <= 10099.0){
        vPos.xz -= windStr * 0.10;
        return vPos;
    }
    // Single/double grounded cutouts (grass, tall grass)
    if(id >= 10600.0 && id <= 10799.0){
        float isUpper = midY - (id >= 10700.0 ? 1.5 : 0.5);
        vPos.xz += isUpper * windStr * 0.10;
        return vPos;
    }
    // Hanging cutouts (vines, etc.)
    if(id >= 10800.0 && id <= 10899.0){
        float isLower = midY + 0.5;
        vPos.xz += isLower * windStr * 0.05;
        return vPos;
    }
    // Wall/multi cutouts
    if(id >= 10900.0 && id <= 10999.0){
        vPos.xz += windStr * 0.05;
        return vPos;
    }

    if(CURRENT_SPEED > 0.0){
        float curStr = cos(-sumOf(wXZ) * CURRENT_FREQUENCY + t * CURRENT_SPEED);
        if(id >= 11100.0 && id <= 11199.0){
            vPos.y += curStr * 0.05;
            return vPos;
        }
        if(id >= 11600.0 && id <= 11799.0){
            float isUpper = midY - (id >= 11700.0 ? 1.5 : 0.5);
            vPos.xz += isUpper * curStr * 0.10;
            return vPos;
        }
    }
    return vPos;
}

#else
// HIGH: Gusting wind with per-block phase offset and secondary flutter
vec3 getTerrainWave(in vec3 vPos, in vec2 wXZ, in float midY, in float id, in float outside, in float t){
    if(WIND_SPEED <= 0.0) return vPos;

    // Primary gust wave
    vec2 phase = id == 10801 ? floor(wXZ) : wXZ;
    float base  = sin(-sumOf(phase) * WIND_FREQUENCY + t * WIND_SPEED);
    // Secondary rapid flutter (1/3 amplitude, ~2x frequency)
    float flutter = sin(-sumOf(phase * 1.37) * WIND_FREQUENCY * 2.1 + t * WIND_SPEED * 2.3) * 0.33;
    float windStr = (base + flutter) * outside;

    // Gentle turbulence: time-varying gust strength
    float gustMod = 0.85 + 0.30 * sin(t * 0.37 + sumOf(wXZ) * 0.07);
    windStr *= gustMod;

    if(id >= 10000.0 && id <= 10099.0){
        vPos.xz -= windStr * 0.10;
        // Add slight vertical bob for leaves
        vPos.y   += abs(windStr) * 0.02;
        return vPos;
    }
    if(id >= 10600.0 && id <= 10799.0){
        float isUpper = midY - (id >= 10700.0 ? 1.5 : 0.5);
        vPos.xz += isUpper * windStr * 0.11;
        vPos.y  += isUpper * abs(windStr) * 0.015;
        return vPos;
    }
    if(id >= 10800.0 && id <= 10899.0){
        float isLower = midY + 0.5;
        vPos.xz += isLower * windStr * 0.06;
        return vPos;
    }
    if(id >= 10900.0 && id <= 10999.0){
        vPos.xz += windStr * 0.05;
        return vPos;
    }

    if(CURRENT_SPEED > 0.0){
        float curStr = cos(-sumOf(wXZ) * CURRENT_FREQUENCY + t * CURRENT_SPEED);
        if(id >= 11100.0 && id <= 11199.0){
            vPos.y += curStr * 0.05;
            return vPos;
        }
        if(id >= 11600.0 && id <= 11799.0){
            float isUpper = midY - (id >= 11700.0 ? 1.5 : 0.5);
            vPos.xz += isUpper * curStr * 0.10;
            return vPos;
        }
    }
    return vPos;
}
#endif
