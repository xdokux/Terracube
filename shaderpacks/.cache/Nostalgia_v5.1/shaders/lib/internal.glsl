const float indirectResScale = sqrt(1.0 / indirectResReduction);

const int shadowMapResolution = 2048; 	//[512 1024 1536 2048 2560 3072 3584 4096 6144 8192 16384]

#define cloudShadowmapRenderDistance 512.0
#define cloudShadowmapResolution 256

const int noiseTextureResolution = 256;

const int voxelMapRes = int(shadowMapResolution * MC_SHADOW_QUALITY);
const int shadowMapRes = int(shadowMapResolution * MC_SHADOW_QUALITY);

#ifndef DIM
    #define generateShadowmap
#endif

#define ResolutionScale 0.75     //[0.25 0.5 0.75 1.0]

#define blocklightBaseMult 1.0

#define minimumAmbientColor vec3(0.7, 0.7, 1.0)
#define minimumAmbientMult 0.005

#define DEBUG_VIEW 0    //[0 1 2 3 4 5 6] 0-off, 1-whiteworld, 2-indirect light, 3-albedo/unlit, 4-, 5-hdr