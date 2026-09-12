#ifdef RAINBOW_ENCHANTMENTS
	float noise = frameTimeCounter;
	noise += texture2D(noisetex, rainbowPos.xz * invNoiseRes).r;
	noise += texture2D(noisetex, rainbowPos.xy * invNoiseRes).r;
	noise += texture2D(noisetex, rainbowPos.yz * invNoiseRes).r;
	color.rgb = hue(noise) * square(max(max(color.r, color.g), color.b));
#else
	color.rgb *= tint.rgb;
#endif
color.rgb *= tint.a;