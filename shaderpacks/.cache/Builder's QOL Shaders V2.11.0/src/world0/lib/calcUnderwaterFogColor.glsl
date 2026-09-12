vec3 calcUnderwaterFogColor(vec3 color, float blockDist, float brightness) {
	float rainCoefficient = max(rainStrength, wetness);
	vec3 absorb = exp2(-blockDist * mix(waterAbsorbColorWhenSunny, waterAbsorbColorWhenRaining, rainCoefficient));
	vec3 scatter = mix(waterScatterColorWhenSunny, waterScatterColorWhenRaining, rainCoefficient) * (1.0 - absorb) * (brightness * day);
	return color * absorb + scatter;
}

//simpler algorithm for the special case where distance = infinity (for infinite oceans)
vec3 calcUnderwaterFogColorInfinity(float brightness) {
	return mix(waterScatterColorWhenSunny, waterScatterColorWhenRaining, max(rainStrength, wetness)) * (brightness * day);
}