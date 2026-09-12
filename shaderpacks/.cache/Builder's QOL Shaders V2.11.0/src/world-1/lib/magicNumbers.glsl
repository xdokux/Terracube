#include "/lib/magicNumbers.glsl"

const vec3 blockLightColorNearInSoulSandValleys = vec3(0.8,     1.1,     1.4); //color of block lights in soul sand valleys when the player is near a light source.
const vec3 blockLightColorFarInSoulSandValleys  = vec3(0.25,    0.75,    1.5); //color of block lights in soul sand valleys when the player is far away from a light source.
const vec3 ambientLightColorInSoulSandValleys   = vec3(0.03125, 0.125,   0.125);
const vec3 ambientLightColorInOtherBiomes       = vec3(0.125,   0.03125, 0.03125);

const vec3 blockVibrantColorNearInSoulSandValleys = vec3(1.0,  1.1, 1.2); //vibrant color for block lights in soul sand valleys when the player is near a light source.
const vec3 blockVibrantColorFarInSoulSandValleys  = vec3(0.8,  1.0, 1.4); //vibrant color for block lights in soul sand valleys when the player is far away from a light source.
const vec3 ambientVibrantColorInSoulSandValleys   = vec3(0.75, 1.0, 1.5);
const vec3 ambientVibrantColorInOtherBiomes       = vec3(1.5,  1.0, 0.75);
