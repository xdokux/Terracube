#ifdef CROSS_PROCESS
	/*
	#ifdef SOUL_FIRE_INTEGRATION
	#endif
	*/
	#if defined(SOUL_FIRE_INTEGRATION) && MC_VERSION >= 11600
		#ifdef SOUL_LAVA
			float soul = inSoulSandValley;
		#else
			float soul = smoothstep(NETHER_LAVA_LEVEL, NETHER_LAVA_LEVEL + 16.0, pos.world.y) * inSoulSandValley;
		#endif
		vec3 blockCrossColor = mix(
			mix(blocklightVibrantColorFar, blockVibrantColorFarInSoulSandValleys, soul),
			mix(blocklightVibrantColorNear, blockVibrantColorNearInSoulSandValleys, soul),
			eyeBrightnessSmooth.x / 240.0
		);
		vec3 ambientCrossColor = mix(ambientVibrantColorInOtherBiomes, ambientVibrantColorInSoulSandValleys, soul);
		vec3 crossProcessColor = mix(ambientCrossColor, blockCrossColor, lmcoord.x); //final cross-processing color
	#else
		vec3 blockCrossColor = mix(blocklightVibrantColorFar, blocklightVibrantColorNear, eyeBrightnessSmooth.x / 240.0);
		vec3 crossProcessColor = mix(ambientVibrantColorInOtherBiomes, blockCrossColor, lmcoord.x); //final cross-processing color
	#endif
	color.rgb = clamp(color.rgb * crossProcessColor - (color.grr + color.bbg) * vibrantSaturation, 0.0, 1.0);
#endif