const vec3 blockLightColorNear   = vec3(1.0,   0.85,  0.7); //color of block lights when the player is near a light source.
const vec3 blockLightColorFar    = vec3(1.0,   0.5,   0.15); //color of block lights when the player is far away from a light source.
const vec3 nightVisionLightColor = vec3(0.375, 0.375, 0.5);

const vec3 blocklightVibrantColorFar  = vec3(1.4, 1.0, 0.8); //Vibrant color for block lights when standing far away from a light source.
const vec3 blocklightVibrantColorNear = vec3(1.2, 1.1, 1.0); //Vibrant color for block lights when standing near a light source.
const float vibrantSaturation         = 0.1; //Higher numbers mean more saturation when vibrant colors are enabled.

const float waterNoiseScale = 0.0625;
const float waterNoiseSpeed = 2.0;
const float iceNoiseScale   = 1.0;

const float heatRefractionScale          = 0.125;
const float heatRefractionSpeed          = 0.125;
const float heatRefractionInBasaltDeltas = HEAT_REFRACTION * 2.0;

const float lavaOverlayResolution                     = 24.0;
const float lavaOverlayHeatRefractionOffsetMultiplier = lavaOverlayResolution * 2.0;
//final color is noise * lavaOverlayNoiseColor + lavaOverlayBaseColor,
//where noise is in the range -1 to +1.
const vec3 lavaOverlayBaseColor  = vec3(1.0,   0.5, 0.0);
const vec3 lavaOverlayNoiseColor = vec3(0.375, 0.5, 0.5);

//Overworld cloud colors are multi-dimensional because they're used by /lib/fastDrawClouds.glsl for end portal blocks.
//At night, this will be 0.
//When raining, this will be fogColor * 0.5
const vec3 cloudBaseColorDuringSunnyDays = vec3(0.48, 0.5, 0.55);

//At night, both of these will be 0.
const vec3 cloudIlluminationColorWhenSunny   = vec3(1.0,  1.0, 1.0);
const vec3 cloudIlluminationColorWhenRaining = vec3(0.45, 0.5, 0.6);

const float dragonEggJumpAttemptsPerSecond = 2.0;
const float dragonEggJumpSuccessChance     = 0.25;
const float dragonEggMinJumpAmount         = 0.25;
const float dragonEggMaxJumpAmount         = 0.5;
const float dragonEggJumpDecaySpeed        = 3.14159265359;
const float dragonEggRotationSpeed         = 4.0;