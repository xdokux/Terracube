#ifdef CROSS_PROCESS
	vec3 blockCrossColor = mix(blocklightVibrantColorFar, blocklightVibrantColorNear, eyeBrightnessSmooth.x / 240.0); //cross processing color from block lights
	vec3 finalCrossColor = mix(mix(vec3(1.0), skylightVibrantColor, lmcoord.y), blockCrossColor, lmcoord.x); //final cross-processing color (blockCrossColor takes priority over skyCrossColor)
	//vec3(color.g + color.b, color.r + color.b, color.r + color.g)
	color.rgb = clamp(color.rgb * finalCrossColor - (color.grr + color.bbg) * 0.1, 0.0, 1.0);
#endif