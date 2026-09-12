#include "/lib/defines.glsl"

#define END_PORTAL_BACKGROUND_NETHER 2 //1: Use overworld fog color. 2: Use end background. [1 2]
#define END_PORTAL_CLOUDS_NETHER 2 //0: No clouds. 1: Use overworld clouds. 2: Use void clouds. [0 1 2]
#define END_PORTAL_EFFECTS_NETHER //Enables fancy effects for end portals
#define END_PORTAL_FOREGROUND_NETHER 2 //0: No foreground image. 1: Use overworld screenshot. 2: Use end island screenshot. [0 1 2]
#define EYE_ADJUST_NETHER_DARK 2.5 //Brightness multiplier for the whole screen when standing in darkness in the nether [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define EYE_ADJUST_NETHER_LIGHT 1.5 //Brightness multiplier for the whole screen when standing in bright light in the nether [0.5 0.625 0.75 0.875 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0]
#define FOG_DENSITY_MULTIPLIER_NETHER 1.0 //How much overall fog there is in the nether [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
#define FOG_ENABLED_NETHER //Enables fog in the nether
#define LAVA_WAVE_STRENGTH 100 //Adds waves to the nether lava oceans [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define NETHER_LAVA_LEVEL 32.0 //Y level at which lava waves happen. Also controls some soul fire integration logic. [0.0 8.0 16.0 24.0 32.0 40.0 48.0 56.0 64.0 72.0 80.0 88.0 96.0 104.0 112.0 120.0 128.0 136.0 144.0 152.0 160.0 168.0 176.0 184.0 192.0 200.0 208.0 216.0 224.0 232.0 240.0 248.0 256.0]
#define SOUL_FIRE_INTEGRATION //When enabled, block light will be tinted blue in soul sand valleys
#define SOUL_LAVA //When enabled, lava and magma blocks will be blue tinted in soul sand valleys

#define END_PORTAL_BACKGROUND END_PORTAL_BACKGROUND_NETHER
#define END_PORTAL_CLOUDS END_PORTAL_CLOUDS_NETHER
#define END_PORTAL_EFFECTS END_PORTAL_EFFECTS_NETHER
#define END_PORTAL_FOREGROUND END_PORTAL_FOREGROUND_NETHER