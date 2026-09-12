vec3 calcFogColor(vec3 viewPosNorm) {
	float upDot = dot(viewPosNorm, upPosNorm) * 2.0;
	float sunDot = dot(viewPosNorm, sunPosNorm) * 0.5 + 0.5;
	float rainCoefficient = max(rainStrength, wetness);
	vec3 color;
	vec3 skyclr = skyColor;
	skyclr.rg = mix(skyclr.bb, skyclr.rg, OVERWORLD_SKY_SATURATION_BOOST);
	skyclr = mix(skyclr, fogColor * 0.65, rainCoefficient);
	vec3 fogclr = fogColor;
	fogclr.rg = mix(fogclr.bb, fogclr.rg, OVERWORLD_FOG_SATURATION_BOOST);
	fogclr *= (1.0 - rainCoefficient * 0.25) * (1.0 - nightVision * night * 0.75);

	if (upDot > 0.0) color = skyclr + nightSkyColor * (1.0 - day) * (1.0 - rainStrength); //avoid pitch black sky at night
	else color = fogclr;

	if (sunset > 0.001 && rainCoefficient < 0.999) {
		vec3 sunsetColor = interpolateSmooth3(clamp(sunsetColorForSky - adjustedTime + upDot + sunDot * 0.2 * (1.0 - night), 0.0, 1.0)); //main sunset gradient
		sunsetColor = mix(fogclr, sunsetColor, (sunDot * 0.5 + 0.5) * sunset * (1.0 - rainCoefficient)); //fade in at sunset and out when not looking at the sun
		color = mix(color, sunsetColor, fogify(upDot, OVERWORLD_HORIZON_HEIGHT)); //mix with final color based on how close we are to the horizon
	}
	else if (upDot > 0.0) color = mix(color, fogclr, fogify(upDot, OVERWORLD_HORIZON_HEIGHT));

	#ifdef RAINBOWS
		float rainbowStrength = (wetness - rainStrength) * day * 0.25;
		float rainbowHue = (sunDot - rainbowPosition) * rainbowThinness;
		if (rainbowStrength > 0.01 && rainbowHue > 0.0 && rainbowHue < 1.0) {
			rainbowHue *= 6.0;
			color += clamp(vec3(1.5, 2.0, 1.5) - abs(rainbowHue - vec3(1.5, 3.0, 4.5)), 0.0, 1.0) * rainbowStrength;
			//color.r += clamp(1.5 - abs(rainbowHue - 1.5), 0.0, 1.0) * rainbowStrength;
			//color.g += clamp(2.0 - abs(rainbowHue - 3.0), 0.0, 1.0) * rainbowStrength;
			//color.b += clamp(1.5 - abs(rainbowHue - 4.5), 0.0, 1.0) * rainbowStrength;
		}
	#endif

	return color;
}