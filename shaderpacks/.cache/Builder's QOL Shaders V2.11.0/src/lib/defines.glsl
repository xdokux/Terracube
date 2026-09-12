#define ALT_GLASS //Uses alternate blending method for stained glass which looks more like real stained glass
#define BLUR_ENABLED //Is blur enabled at all?
#define BLUR_QUALITY 10 //Maximum number of sample points to use for blurring. Higher limit = higher performance impact! [5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
//#define BRIGHT_PORTAL_FIX //Enable this if end portals are 16x brighter than they should be
#define BRIGHT_WATER //Overrides light levels under water to be higher
#define CLEAR_WATER //Overwrites water texture to be completely transparent
#define CLOUDS //3D clouds (partially volumetric too). Mild performance impact!
//#define CROSS_PROCESS //Opposite of desaturation, makes everything more vibrant and saturated.
#define DOF_STRENGTH 0 //Blurs things that are at a different distance than whatever's in the center of your screen [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define DYNAMIC_LIGHT_FLICKER 8 //How much certain dynamic lights (like torches) will flicker [0 1 2 3 4 5 6 8 12 16 24 32 48 64]
#define DYNAMIC_LIGHT_VIGNETTE 50 //Reduces the brightness of dynamic light around edges the of your screen [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define DYNAMIC_LIGHTS //Holding blocks that emit light will light up their surroundings
#define ENDER_ARCS //Adds bolts of plasma that arc through the nebulae. Requires ender nebulae to be enabled!
#define ENDER_NEBULAE //Adds animated nebulae to the background of the end dimension
#define ENDER_STARS //Adds blinking stars to the background of the end dimension. Stackable with nebulae/plasma.
#define FANCY_BEACONS //Builderb0y's better beacon beams bring big bright beautiful beacon beams to all biomes, bro
#define GLASS_BLUR 8 //Blurs things behind stained glass [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define GRASS_AO //Adds ambient occlusion to tallgrass/flowers/etc... Works best with "Remove Y Offset" enabled.
#define GRASS_PATCHES //Makes grass less uniform by making patches of it dryer or lusher. Does not affect leaves.
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
#define HUMIDITY_OFFSET 1.1 //Higher number = lusher grass. Lower number = dryer grass [0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.25]
#define ICE_BLUR 4 //Blurs things behind ice [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define ICE_NORMALS //Distorts things reflected by ice. Has no effect when reflections are disabled!
#define ICE_REFRACT //Distorts things behind ice
#define IDLE_HANDS //Makes your hands sway back and forth in 1st person, like they do in 3rd person
#define JUMPING_DRAGON_EGGS //Makes dragon eggs jump and wobble, as if they were about to hatch
#define LAVA_PATCHES //Randomizes lava brightness, similar to grass patches
//#define LEGACY_SUGARCANE //Removes biome coloring from sugar cane
//#define OLD_CLOUDS //Makes fancy clouds more square-shaped
#define RAINBOW_ENCHANTMENTS //If enabled, the enchantment glint will be rainbow instead of the default purple color
#define REFLECT //Reflects the sun/sky onto reflective surfaces. Does not add reflections of terrain!
#define REFRACT_AMOUNT 1.00 //Multiplier for the amount of refraction applied to water [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00 2.50 3.00 3.50 4.00 4.50 5.00]
//#define REMOVE_XZ_OFFSET //Removes random X/Z offset from tallgrass/flowers/etc...
//#define REMOVE_Y_OFFSET //Removes random Y offset from tallgrass/flowers/etc...
#define THRESHOLD_ALPHA 0.6 //Anything above this opacity counts as part of the border of stained glass, and will not apply blur/reflection effects [0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95]
#define UNDERWATER_BLUR 8 //Blurs the world while underwater [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define UNDERWATER_FOG //Applies fog to water
//#define VANILLA_LIGHTMAP //Uses vanilla light colors instead of custom ones. Requires optifine 1.12.2 HD_U_D1 or later!
#define VOID_CLOUDS //Dark ominous clouds in the end
#define WATER_BLUR 4 //Blurs things behind water [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]
#define WATER_NORMALS //Distorts things reflected by water. Has no effect when reflections are disabled!
#define WATER_REFRACT //Distorts things behind water
#define WATER_WAVE_STRENGTH 50 //Makes overworld oceans move up and down [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define WAVING_GRASS //Adds wind effects to grass
//#define WAVING_LEAVES //Adds wind effects to leaves
//#define WAVING_VINES //Adds wind effects to vines