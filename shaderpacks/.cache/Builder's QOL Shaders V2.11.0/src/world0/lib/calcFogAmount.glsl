float calcFogAmount(inout Position pos, in float fogDistance) {
	float fogDensity = exp2(
		(
			//equivalen to: (pos.world.y - SEA_LEVEL) * (-1.0 / FOG_HEIGHT_MULTIPLIER_OVERWORLD)
			pos.world.y
			* (-1.0 / FOG_HEIGHT_MULTIPLIER_OVERWORLD)
			+ (SEA_LEVEL / FOG_HEIGHT_MULTIPLIER_OVERWORLD)
		)
		* (1.0 - rainStrength)
		+ (rainStrength * 2.0)
	)
	* FOG_DENSITY_MULTIPLIER_OVERWORLD;
	return fogify(fogDistance * fogDensity, 1.0);
}