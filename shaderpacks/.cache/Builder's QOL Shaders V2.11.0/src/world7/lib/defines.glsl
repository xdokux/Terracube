#include "/lib/defines.glsl"

#define END_PORTAL_BACKGROUND_TF 2 //1: Use overworld fog color. 2: Use end background. [1 2]
#define END_PORTAL_CLOUDS_TF 2 //0: No clouds. 1: Use overworld clouds. 2: Use void clouds. [0 1 2]
#define END_PORTAL_EFFECTS_TF //Enables fancy effects for end portals
#define END_PORTAL_FOREGROUND_TF 2 //0: No foreground image. 1: Use overworld screenshot. 2: Use end island screenshot. [0 1 2]
#define EYE_ADJUST_TF_DARK 3.0 //Brightness multiplier for the whole screen when standing in darkness in the twilight forest [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define EYE_ADJUST_TF_LIGHT 1.5 //Brightness multiplier for the whole screen when standing in bright light in the twilight forest [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define FOG_DISTANCE_MULTIPLIER_TF 0.25 //How far away fog starts to appear in the twilight forest [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
#define FOG_ENABLED_TF //Enables fog in the twilight forest
#define TF_AURORAS //Adds auroras to the sky in the twilight forest
#define TF_HORIZON_HEIGHT 0.05 //How far above the horizon the fog color will be applied [0.001 0.002 0.003 0.004 0.005 0.0075 0.01 0.02 0.03 0.04 0.05 0.075 0.1 0.2 0.3 0.4 0.5 0.75 1.0]
#define TF_SKY_FIX //Enable this if the sky looks wrong in the twilight forest

#define END_PORTAL_BACKGROUND END_PORTAL_BACKGROUND_TF
#define END_PORTAL_CLOUDS END_PORTAL_CLOUDS_TF
#define END_PORTAL_EFFECTS END_PORTAL_EFFECTS_TF
#define END_PORTAL_FOREGROUND END_PORTAL_FOREGROUND_TF
