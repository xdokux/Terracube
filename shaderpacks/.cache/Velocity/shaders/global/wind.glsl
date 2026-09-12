// Helios: improved foliage wind.
//
// Replaces mellow's single-sine `sin(x)*sin(y)*sin(z)` swaying with:
//   - Multi-octave wind (1/2/3 octaves, controlled by HELIOS_WIND_OCTAVES)
//   - Gusts: low-frequency amplitude modulation (HELIOS_WIND_GUST)
//   - Per-plant phase variation: plants next to each other don't wave in sync
//   - Height-based bending: tips move more than bases (using texcoord.t)
//   - Plant-type-aware stiffness (HELIOS_WIND_STIFFNESS)
//
// This file is included by gbuffers_terrain.vsh, gbuffers_water.vsh, and
// shadow.vsh so the swaying is consistent across the scene + shadow map.

// Hash-based per-plant phase. Uses the plant's world position snapped to
// the block grid so each block gets a stable but unique phase offset.
float helios_plant_phase(vec3 WorldPos) {
    // Snap to block centers and hash. Cheap integer hash.
    vec3 p = floor(WorldPos);
    float h = fract(p.x * 0.1031 + p.y * 0.1030 + p.z * 0.0973);
    h = fract(h * 33.33 + 0.51);
    return h * TAU;
}

// Gust envelope: a slow sine that modulates wind strength over ~10 seconds.
// This is what makes the wind feel "alive" rather than constant.
float helios_wind_gust(vec3 WorldPos) {
    #if HELIOS_WIND_GUST > 0.001
        // Two slow sines at slightly different frequencies -> beat pattern
        // that produces irregular gusts.
        float t = frameTimeCounter * 0.35;
        float g1 = sin(t + WorldPos.x * 0.03 + WorldPos.z * 0.02);
        float g2 = sin(t * 0.7 + WorldPos.x * 0.02 - WorldPos.z * 0.025);
        float Gust = (g1 * 0.6 + g2 * 0.4) * 0.5 + 0.5; // remap to 0..1
        // Apply HELIOS_WIND_GUST as the modulation depth.
        return mix(1.0, Gust * 1.4, HELIOS_WIND_GUST);
    #else
        return 1.0;
    #endif
}

// Multi-octave wind displacement. Returns a scalar amplitude in roughly
// the [-1, 1] range. The caller scales it by WAVE_AMPLITUDE.
//
// Octave 1: large-scale swell (low freq, high amplitude)
// Octave 2: medium turbulence (mid freq, half amplitude)
// Octave 3: small ripples (high freq, quarter amplitude) - optional
float helios_wind_amplitude(vec3 WorldPos, float PhaseOffset) {
    float t = frameTimeCounter * WAVE_SPEED;
    vec3 p = WorldPos / WAVE_SIZE;

    // Octave 1: the base swell. Slightly rotated direction so plants don't
    // all wave in perfect sync along axes.
    float o1 = sin(p.x + t + PhaseOffset) * cos(p.z + t * 0.8 + PhaseOffset * 0.7);

    float Amp = o1;

    #if HELIOS_WIND_OCTAVES >= 2
        // Octave 2: medium turbulence, perpendicular direction, half amplitude.
        float o2 = sin(p.z * 2.3 + t * 1.3 + PhaseOffset * 1.4) *
                   cos(p.x * 1.8 - t * 1.1 + PhaseOffset * 0.5);
        Amp += o2 * 0.5;
    #endif

    #if HELIOS_WIND_OCTAVES >= 3
        // Octave 3: small ripples, quarter amplitude, fast.
        float o3 = sin(p.x * 4.7 + p.z * 3.1 + t * 2.1 + PhaseOffset * 2.1);
        Amp += o3 * 0.25;
    #endif

    #if HELIOS_WIND_OCTAVES >= 2
        // Renormalize so the multi-octave version has roughly the same peak
        // amplitude as the single-octave version.
        Amp /= 1.75;
    #endif

    return Amp;
}

// Height factor: how much of the plant's height this vertex represents.
// Tips (top of the texture, gl_MultiTexCoord0.t < mc_midTexCoord.t) get
// full amplitude; bases get ~0.3 (a little bit of motion at the base
// looks more natural than a completely rigid root).
//
// `IsUpperHalf` is true when this vertex is in the top half of the plant
// (the part that should sway). The caller determines this via texcoord.
float helios_height_factor(bool IsUpperHalf) {
    return IsUpperHalf ? 1.0 : 0.3;
}

// Plant-type stiffness multipliers. Different plant types bend differently:
//   - Leaves (10002): stiff, sway as a unit, small amplitude
//   - Tall grass / ferns (10004): flexible, large amplitude
//   - Small flowers / crops (10005): medium
//   - Stems / vines (10006): very flexible at the top, stiff at the base
float helios_plant_stiffness(float material) {
    float S = 1.0 / HELIOS_WIND_STIFFNESS;
    if (material == 10002) {
        // Leaves: 0.5x amplitude (stiff canopy)
        return S * 0.5;
    } else if (material == 10004) {
        // Tall grass / ferns: 1.2x amplitude (floppy)
        return S * 1.2;
    } else if (material == 10005) {
        // Small flowers / crops: 0.8x amplitude
        return S * 0.8;
    } else if (material == 10006) {
        // Stems / vines: 1.0x amplitude
        return S * 1.0;
    }
    return S;
}

// Main entry point: compute the world-space displacement for a foliage vertex.
// `WorldPos` is the player-space position + cameraPosition (i.e. true world pos).
// `material` is the mc_Entity.x value.
// `IsUpperHalf` is true if the vertex is in the top half of the plant texture.
// Returns a vec3 displacement to ADD to WorldPos.
vec3 helios_foliage_wind(vec3 WorldPos, float material, bool IsUpperHalf) {
    #ifndef HELIOS_FOLIAGE_WIND
        // Fallback: mellow's original single-sine swaying.
        vec3 WavePos = WorldPos / WAVE_SIZE + frameTimeCounter * WAVE_SPEED;
        WavePos = sin(WavePos);
        float Noise = WavePos.x * WavePos.y * WavePos.z;
        Noise *= WAVE_AMPLITUDE + rainStrength * 0.1 + linstep(100, 150, WorldPos.y) * 0.1;
        return vec3(Noise);
    #else
        // Per-plant phase so neighboring plants don't wave in sync.
        float Phase = helios_plant_phase(WorldPos);
        // Gust modulation.
        float Gust = helios_wind_gust(WorldPos);
        // Multi-octave amplitude.
        float Amp = helios_wind_amplitude(WorldPos, Phase);

        // Height-based bending: tips move more than bases.
        float HeightFactor = helios_height_factor(IsUpperHalf);

        // Plant-type stiffness.
        float Stiffness = helios_plant_stiffness(material);

        // Rain adds a bit of extra motion (drops hitting leaves).
        float RainBoost = 1.0 + rainStrength * 0.15;

        // Combine. The displacement is mostly horizontal (xz) with a tiny
        // vertical component for leaves to simulate fluttering.
        float FinalAmp = Amp * WAVE_AMPLITUDE * Gust * HeightFactor * Stiffness * RainBoost;

        // Wind direction: mostly along +x with a bit of +z, modulated by the
        // per-plant phase so it's not perfectly uniform.
        vec3 Dir = normalize(vec3(0.85, 0.0, 0.45) + vec3(sin(Phase) * 0.2, 0.0, cos(Phase) * 0.2));

        vec3 Displacement = Dir * FinalAmp;

        // Leaves get a small vertical flutter on top of the horizontal sway.
        #ifdef WAVE_LEAVES
        if (material == 10002) {
            Displacement.y += sin(Phase + frameTimeCounter * WAVE_SPEED * 1.7) * FinalAmp * 0.3;
        }
        #endif

        return Displacement;
    #endif
}
