#include "/lib/defines.glsl"

#define DESATURATE_END 0.25 //Amount to desaturate the end dimension [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define END_PORTAL_BACKGROUND_END 1 //1: Use overworld fog color. 2: Use end background. [1 2]
#define END_PORTAL_CLOUDS_END 1 //0: No clouds. 1: Use overworld clouds. 2: Use void clouds. [0 1 2]
#define END_PORTAL_EFFECTS_END //Enables fancy effects for end portals
#define END_PORTAL_FOREGROUND_END 1 //0: No foreground image. 1: Use overworld screenshot. 2: Use end island screenshot. [0 1 2]
#define EYE_ADJUST_END_DARK 1.5 //Brightness multiplier for the whole screen when standing in darkness in the end [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define EYE_ADJUST_END_LIGHT 1.0 //Brightness multiplier for the whole screen when standing in bright light in the end [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define FOG_DISTANCE_MULTIPLIER_END 0.25 //How far away fog starts to appear in the end [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
//#define FOG_ENABLED_END //Enables fog in the end
#define VOID_CLOUD_HEIGHT 128.0 //Y level of void clouds [-64.0 -48.0 -32.0 -16.0 0.0 16.0 32.0 48.0 64.0 80.0 96.0 112.0 128.0 144.0 160.0 176.0 192.0 208.0 224.0 240.0 256.0 272.0 288.0 304.0 320.0 336.0 352.0 368.0 384.0 400.0 416.0 432.0 448.0 464.0 480.0 496.0 512.0]

#define END_PORTAL_BACKGROUND END_PORTAL_BACKGROUND_END
#define END_PORTAL_CLOUDS END_PORTAL_CLOUDS_END
#define END_PORTAL_EFFECTS END_PORTAL_EFFECTS_END
#define END_PORTAL_FOREGROUND END_PORTAL_FOREGROUND_END
