#define DH_NOISE
#define DH_CUTOFF 16 // [0 16 32 48 64 80 96 128]
#define DH_NOISE_SIZE 8 // [2 4 8 16 32 64]

#ifdef DISTANT_HORIZONS
    #define farLod dhRenderDistance
#else
    #define farLod far
#endif


vec3 dh_noise(vec3 PlayerPos, vec3 Color) {
    vec3 WorldPos = PlayerPos + cameraPosition + gbufferModelViewInverse[3].xyz;
    vec3 NoisePos = floor(WorldPos * DH_NOISE_SIZE + 0.001) / DH_NOISE_SIZE;
    Color *= exp(-random3D(NoisePos) / 4) + 0.104;
    return clamp(Color, 0, 1);
}

bool transition_to_dh(vec3 PlayerPos, float Dither) {
    #ifdef DH_TERRAIN
        const bool IsDHPass = true;
    #else
        const bool IsDHPass = false;
    #endif
    float Bias = float(IsDHPass) * far / 32; // Needed because of depth imprecision i think
    float Fade = float(!IsDHPass) * Dither * 8;
    bool IsDH = length(PlayerPos) > far - DH_CUTOFF - Bias + Fade;
    return IsDHPass ? !IsDH : IsDH;
}