// DONTOPTIMIZE-START

#if (defined DIMENSION_OVERWORLD) || (!defined CUSTOM_SKYBOXES)
const bool colortex0Clear = false;
#endif
const bool colortex1Clear = false;
const bool colortex2Clear = false;
const bool colortex3Clear = false;
const bool gaux1Clear = false;
const bool colortex5Clear = false;
const bool shadowcolor0Clear = false;

const vec4 colortex0ClearColor = vec4(0, 0, 0, 1);
const vec4 colortex1ClearColor = vec4(0,0,0,1);

const float shadowDistanceRenderMul = 1.0;
const bool shadowHardwareFiltering = true;

/*
const int colortex0Format = R11F_G11F_B10F;
const int colortex1Format = R11F_G11F_B10F;
const int colortex2Format = RGBA8;
const int gaux1Format = R11F_G11F_B10F;
const int shadowcolor0Format = R3_G3_B2;
const int colortex5Format = RG16; 
*/

#if SUN_PATH_ROTATION == -40
    const float sunPathRotation = -40;
#elif SUN_PATH_ROTATION == -35
    const float sunPathRotation = -35;
#elif SUN_PATH_ROTATION == -30
    const float sunPathRotation = -30;
#elif SUN_PATH_ROTATION == -25
    const float sunPathRotation = -25;
#elif SUN_PATH_ROTATION == -20
    const float sunPathRotation = -20;
#elif SUN_PATH_ROTATION == -15
    const float sunPathRotation = -15;
#elif SUN_PATH_ROTATION == 0
    const float sunPathRotation = 0;
#elif SUN_PATH_ROTATION == 15
    const float sunPathRotation = 15;
#elif SUN_PATH_ROTATION == 20
    const float sunPathRotation = 20;
#elif SUN_PATH_ROTATION == 25
    const float sunPathRotation = 25;
#elif SUN_PATH_ROTATION == 30
    const float sunPathRotation = 30;
#elif SUN_PATH_ROTATION == 35
    const float sunPathRotation = 35;
#elif SUN_PATH_ROTATION == 40
    const float sunPathRotation = 40;
#else
    const float sunPathRotation = SUN_PATH_ROTATION; // Doesn't work with optifine
#endif

// DONTOPTIMIZE-END