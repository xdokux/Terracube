vec3 calcUnderwaterFogColor(vec3 color, float dist, float brightness) {
	vec3 absorb = exp2(-dist * waterAbsorbColor);
	vec3 scatter = waterScatterColor * (1.0 - absorb) * brightness;
	return color * absorb + scatter;
}

vec3 calcUnderwaterFogColorInfinity(float brightness) {
	//simpler algorithm for the special case where distance = infinity (for looking at unobstructed sky while underwater)
	return waterScatterColor * brightness;
}