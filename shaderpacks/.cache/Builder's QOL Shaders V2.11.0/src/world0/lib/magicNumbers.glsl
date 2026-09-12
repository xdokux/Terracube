#include "/lib/magicNumbers.glsl"

#ifdef CROSS_PROCESS
	const vec3 sunGlowColor  = vec3(1.0,   1.0,   1.0 ); //Mixed with sky color based on distance from sun
	const vec3 moonGlowColor = vec3(0.075, 0.1,   0.2 ); //Mixed with sky color based on distance from moon
	const vec3 nightSkyColor = vec3(0.02,  0.025, 0.05); //Added to sky color at night to avoid it being completely black
#else
	const vec3 sunGlowColor  = vec3(0.8,   0.9,   1.0 ); //Mixed with sky color based on distance from sun
	const vec3 moonGlowColor = vec3(0.1,   0.1,   0.2 ); //Mixed with sky color based on distance from moon
	const vec3 nightSkyColor = vec3(0.025, 0.025, 0.05); //Added to sky color at night to avoid it being completely black
#endif

const vec3 sunsetColorForSky = vec3(7.2, 6.7, 6.2); //Subtract 6.0 from this to get the color of the horizon at sunset.
//Roughly corresponds to the color a bit above the horizon at sunset,
//or the horizon itself a bit before sunset.
//usages include:
//	color of skylight at sunset
//	color of light applied to my fancy clouds
const vec3 sunsetColorForOtherThings = sunsetColorForSky + vec3(0.2, 0.2, 0.2);

const float rainbowPosition =   0.25; //1.0 will be on top of the sun, 0.0 will be on top of the moon.
const float rainbowThinness = -24.0; //Positive numbers will make red be on the inside and blue on the outside.

//Absorb colors are a bit odd in that higher numbers mean
//that the color gets *darker* more quickly with distance.
const vec3 waterAbsorbColorWhenSunny   = vec3(0.2,   0.05,   0.1);
const vec3 waterAbsorbColorWhenRaining = vec3(0.125, 0.0625, 0.25);

const vec3 waterScatterColorWhenSunny   = vec3(0.05,    0.4, 0.5);
const vec3 waterScatterColorWhenRaining = vec3(0.09375, 0.1, 0.15);

const vec3 skylightColorDuringTheDay = vec3(1.0,  1.0, 1.0);
const vec3 skylightColorAtNight      = vec3(0.05, 0.1, 0.15); //If hardcore darkness is enabled, this will be 0 instead.

const vec3 skylightVibrantColorDuringTheDay = vec3(1.4, 1.2, 1.1);
const vec3 skylightVibrantColorAtNight      = vec3(1.0, 1.1, 1.4);
const vec3 skylightVibrantColorWhenRaining  = vec3(1.0, 1.0, 1.0); //Overrides both day and night.

const vec3 cloudIlluminationColorFromFullMoon  = vec3(0.1,  0.15, 0.25);
const vec3 cloudIlluminationColorFromNewMoon   = vec3(0.01, 0.02, 0.03);
const vec3 cloudIlluminationColorFromLightning = vec3(0.9,  0.95, 1.0 );

const vec3 sunReflectionColorDuringTheDay = vec3(1.0, 0.875, 0.75);
const vec3 sunReflectionColorAtSunset     = vec3(1.0, 0.5,   0.25);

//ok so the math of my sun reflections is a bit non-intuitive.
//increasing the brightness will do just that, but it also makes the sun look bigger.
//increasing the inverse brightness will make it darker without changing the size very much.
//the two of these can be used to make the sun look as big or bright as you want,
//but it will probably a bit of experimentation to get the sun to look exactly the way you want.
const float sunReflectionBrightness        = 0.025; //this value should be slightly bigger than 0.
const float sunReflectionInverseBrightness = 1.001; //this value should be slightly bigger than 1.