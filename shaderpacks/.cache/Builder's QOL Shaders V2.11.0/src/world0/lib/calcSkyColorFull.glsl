vec3 calcSkyColor(inout Position pos) {
	float upDot = pos.playerNorm.y * pos.spaceFactor * 0.5; //not much, what's up with you?
	float space = 4.0 / pos.spaceFactor;
	bool top = upDot > 0.0;
	float sunDot = pos.sunDot * 0.5 + 0.5;
	float rainCoefficient = max(rainStrength, wetness);
	vec3 color;
	vec3 skyclr = skyColor;
	skyclr.rg = mix(skyclr.bb, skyclr.rg, OVERWORLD_SKY_SATURATION_BOOST);
	skyclr = mix(skyclr, fogColor * 0.65, rainCoefficient) * space;
	vec3 fogclr = fogColor;
	fogclr.rg = mix(fogclr.bb, fogclr.rg, OVERWORLD_FOG_SATURATION_BOOST);
	fogclr *= (1.0 - rainCoefficient * 0.25) * (1.0 - nightVision * night * 0.75);

	#ifdef RAINBOWS
		float rainbowStrength = (wetness - rainStrength) * day * 0.25;
		float rainbowHue = (sunDot - rainbowPosition) * rainbowThinness;
		if (rainbowStrength > 0.0 && rainbowHue > 0.0 && rainbowHue < 1.0) {
			rainbowHue *= 6.0;
			vec3 rainbowColor = clamp(vec3(1.5, 2.0, 1.5) - abs(rainbowHue - vec3(1.5, 3.0, 4.5)), 0.0, 1.0) * rainbowStrength;
			skyclr += rainbowColor * space * space;
			fogclr += rainbowColor;
		}
	#endif

	if (top) {
		color = skyclr + nightSkyColor * (1.0 - day) * (1.0 - rainStrength) * space; //avoid pitch black sky at night
		if (day > 0.001) color = mix(color, sunGlowColor,  0.75 / ((1.0 - sunDot) * 16.0 + 1.0) * day   * (1.0 - rainStrength * 0.75) * space); //make the sun illuminate the sky around it
		else             color = mix(color, moonGlowColor, 0.75 / (       sunDot  * 16.0 + 1.0) * night * (1.0 - rainStrength       ) * space * phase); //make the moon illuminate the sky around it
	}
	else color = fogclr;

	if (sunset > 0.001 && rainCoefficient < 0.999) {
		vec3 sunsetColor = interpolateSmooth3(clamp(sunsetColorForSky - adjustedTime + upDot + sunDot * 0.2 * (1.0 - night), 0.0, 1.0)); //main sunset gradient
		sunsetColor = mix(fogclr, sunsetColor, (sunDot * 0.5 + 0.5) * sunset * (1.0 - rainCoefficient)); //fade in at sunset and out when not looking at the sun
		color = mix(color, sunsetColor, fogify(upDot, OVERWORLD_HORIZON_HEIGHT)); //mix with final color based on how close we are to the horizon
	}
	else if (top) color = mix(color, fogclr, fogify(upDot, OVERWORLD_HORIZON_HEIGHT));

	#if defined(FANCY_STARS) || defined(GALAXIES)
		color += drawStars(pos);
	#endif

	color += fract(dot(gl_FragCoord.xy, vec2(0.25, 0.5))) * 0.00390625; //dither

	return color;
}