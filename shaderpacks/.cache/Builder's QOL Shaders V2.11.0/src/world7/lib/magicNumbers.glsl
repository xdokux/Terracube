#include "/lib/magicNumbers.glsl"

const vec3 skylightVibrantColor = vec3(1.1, 1.4, 1.2);

//Absorb colors are a bit odd in that higher numbers mean
//that the color gets *darker* more quickly with distance.
const vec3 waterAbsorbColor  = vec3(0.2,  0.05, 0.1);
const vec3 waterScatterColor = vec3(0.05, 0.4,  0.5);