#ifdef CROSS_PROCESS
	vec3 blockCrossColor = mix(blocklightVibrantColorFar, blocklightVibrantColorNear, eyeBrightnessSmooth.x / 240.0); //cross processing color from block lights
	vec3 finalCrossColor = mix(ambientVibrantColor, blockCrossColor, blocklight);
	color.rgb = clamp(color.rgb * finalCrossColor - (color.grr + color.bbg) * 0.1, 0.0, 1.0);
#endif