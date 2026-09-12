// ============================================================
//  CinematicVanilla V2 - wetSurface.glsl   (NEW in V2)
//  Rain darkening + specular boost + animated puddle ripples.
//  Include from gbuffers_terrain.fsh and composite.fsh.
// ============================================================

#ifdef WET_SURFACES

// ─── Surface Wetness ────────────────────────────────────────────────────────
// Darkens diffuse albedo and increases smoothness when raining.
// upness: dot(worldNormal, UP) — only top-facing surfaces get wet.
// Returns modified smoothness.
float applyWetness(inout vec3 albedo, in float smoothness, in float upness){
    float wetness = rainStrength * saturate(upness);
    // Darken albedo (wet surfaces absorb more light)
    albedo *= 1.0 - wetness * 0.30;
    // Boost specular (water film = high gloss)
    float wetSmooth = mix(smoothness, 0.92, wetness * 0.75);
    return wetSmooth;
}

// ─── Puddle Ripples ─────────────────────────────────────────────────────────
#ifdef WET_PUDDLES
// Adds animated ring ripples to the normal when it's raining.
// worldPosXZ: the block-space XZ position for stable anchoring.
// Returns a normal perturbation in tangent space (XY).
vec2 getPuddleRipple(in vec2 worldPosXZ){
    float t    = fragmentFrameTime;
    float rain = rainStrength;
    if(rain < 0.01) return vec2(0.0);

    // Two drop centers randomly seeded by block coords
    vec2 cell1 = floor(worldPosXZ * 0.5) * 2.0 + 0.5;
    vec2 cell2 = floor(worldPosXZ * 0.3 + vec2(7.3, 3.7)) * 3.0 + 1.5;

    // Ripple radius expands over time (wraps every 1.6s)
    float r1 = fract(t * 0.625);
    float r2 = fract(t * 0.625 + 0.5); // offset phase

    float d1 = length(worldPosXZ - cell1);
    float d2 = length(worldPosXZ - cell2);

    // Thin ring at expanding radius, fades in/out
    float ring1 = exp(-abs(d1 - r1 * 2.0) * 8.0) * (1.0 - r1);
    float ring2 = exp(-abs(d2 - r2 * 2.0) * 8.0) * (1.0 - r2);

    // Normal perturbation: outward from drop center
    vec2 norm1 = (d1 > 0.01) ? normalize(worldPosXZ - cell1) * ring1 : vec2(0.0);
    vec2 norm2 = (d2 > 0.01) ? normalize(worldPosXZ - cell2) * ring2 : vec2(0.0);

    return (norm1 + norm2) * rain * 0.04;
}
#endif // WET_PUDDLES

#endif // WET_SURFACES
