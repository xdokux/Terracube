skyLightColor = skylightColorDuringTheDay * day;
shadowColor = mix(skyColor, fogColor, rainStrength);

if (sunset > 0.01) {
	vec3 sunsetColor = clamp(sunsetColorForOtherThings - adjustedTime, 0.0, 1.0); //color of sunset gradient at the horizon, and mix level
	if (rainStrength > 0.001) sunsetColor = mix(sunsetColor, fogColor * (1.0 - rainStrength * 0.5), rainStrength * 0.625); //reduce redness intensity when raining
	sunsetColor   *= sunset;
	skyLightColor += sunsetColor;
	shadowColor   += sunsetColor;
}

#if HARDCORE_DARKNESS == 0
	skyLightColor += skylightColorAtNight * (1.0 - day);
#elif HARDCORE_DARKNESS == 1
	//skyLightColor += vec3(0.0);
#elif HARDCORE_DARKNESS == 2
	skyLightColor += skylightColorAtNight * ((1.0 - day) * phase);
#else
	#error HARDCORE_DARKNESS should be set to 0, 1, or 2.
#endif