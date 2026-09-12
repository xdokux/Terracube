// ============================================================
//  CinematicVanilla V2 - water.glsl
//  Improved water: FBM waves, depth-tint, underwater distortion
// ============================================================

// ─── Wave Noise ─────────────────────────────────────────────────────────────

#if WATER_WAVE_QUALITY == 0
// Flat water — no waves (LOW preset)
float getCellNoise(in vec2 uv, in float t){ return 0.5; }
float getCellNoise(in vec2 uv){ return 0.5; }

#elif WATER_WAVE_QUALITY == 1
// Medium: 2-octave FBM
float getCellNoise(in vec2 uv, in float t){
    float n1 = textureLod(noisetex, uv + t, 0).z;
    float n2 = textureLod(noisetex, uv * 1.73 - t * 0.65, 0).z;
    return n1 * 0.65 + n2 * 0.35;
}
float getCellNoise(in vec2 uv){
    const float cs = CURRENT_SPEED * 0.0625;
    float t = fragmentFrameTime * cs;
    return getCellNoise(uv, t) + getCellNoise(uv * 0.5, -t * 0.7);
}

#else
// High: 4-octave FBM with flow distortion
float getCellNoise(in vec2 uv, in float t){
    float n1 = textureLod(noisetex, uv + t, 0).z;
    float n2 = textureLod(noisetex, uv * 1.73 - t * 0.65, 0).z;
    float n3 = textureLod(noisetex, uv * 0.47 + t * 0.30, 0).z;
    float n4 = textureLod(noisetex, uv * 3.10 - t * 1.10, 0).z;
    return n1 * 0.50 + n2 * 0.27 + n3 * 0.15 + n4 * 0.08;
}
float getCellNoise(in vec2 uv){
    const float cs = CURRENT_SPEED * 0.0625;
    float t = fragmentFrameTime * cs;
    vec2 flow = vec2(getCellNoise(uv * 0.6, t * 0.4) - 0.5) * 0.12;
    return getCellNoise(uv + flow, t);
}
#endif

// ─── Normal Map Generation ──────────────────────────────────────────────────

vec4 H2NWater(in vec2 uv){
    const float cs = CURRENT_SPEED * 0.0625;
    const float px = WATER_BLUR_SIZE * 0.00390625;
    const float wd = WATER_BLUR_SIZE * WATER_DEPTH_SIZE;
    float t = fragmentFrameTime * cs;

    float d0 = getCellNoise(uv, t);
    float d1 = getCellNoise(vec2(uv.x + px, uv.y), t);
    float d2 = getCellNoise(vec2(uv.x, uv.y + px), t);
    float d3 = getCellNoise(vec2(uv.x - px * 0.5, uv.y + px * 0.5), t);

    float nx = (d0 - d1) * 1.20 + (d0 - d3) * 0.28;
    float ny = (d0 - d2) * 1.20 + (d3 - d0) * 0.28;

    return vec4(nx, ny, wd, d0);
}

// ─── Depth Color Absorption ──────────────────────────────────────────────────
// Call from gbuffers_water.fsh / composite.fsh to tint water by depth.
// depthM: water depth in meters (positive).  Returns Beer-Lambert absorption.
#ifdef WATER_DEPTH_TINT
vec3 getWaterDepthColor(in float depthM){
    // Beer-Lambert: deeper = more absorbed (warmer reds & greens lost first)
    vec3 absorb = exp(-WATER_DEPTH_COLOR * depthM * WATER_DEPTH_SCALE);
    return absorb;
}
#endif

// ─── Underwater Distortion ──────────────────────────────────────────────────
#ifdef UNDERWATER_BLUR
// Wavy UV warp for underwater screen distortion. Apply to colortex sample UV.
vec2 underwaterDistort(in vec2 uv){
    float t = fragmentFrameTime * 0.4;
    float wx = sin(uv.y * 18.0 + t) * 0.003 + sin(uv.y * 7.0 - t * 0.7) * 0.002;
    float wy = cos(uv.x * 14.0 + t * 0.9) * 0.003 + cos(uv.x * 5.5 - t * 1.3) * 0.0015;
    return uv + vec2(wx, wy);
}
#endif
