#ifdef CROSS_PROCESS
	vec3 skyCrossColor    = mix(mix(skylightVibrantColorDuringTheDay, skylightVibrantColorAtNight, night), skylightVibrantColorWhenRaining, wetness); //cross processing color from the sun
	vec3 blockCrossColor  = mix(blocklightVibrantColorFar, blocklightVibrantColorNear, eyeBrightnessSmooth.x / 240.0); //cross processing color from block lights
	vec3 finalCrossColor  = mix(mix(vec3(1.0), skyCrossColor, lmcoord.y), blockCrossColor, lmcoord.x); //final cross-processing color (blockCrossColor takes priority over skyCrossColor)
	color.rgb = clamp(color.rgb * finalCrossColor - (color.grr + color.bbg) * vibrantSaturation, 0.0, 1.0);
#endif