if (isEyeInWater == 2 && !isSpectator) {
	vec2 coord = texcoord * lavaOverlayResolution + heatRefractionOffset() * lavaOverlayHeatRefractionOffsetMultiplier;
	coord.y = coord.y / aspectRatio + frameTimeCounter;
	coord = floor(coord) + 0.5;
	float noise = 0.0;
	noise += (texture2D(noisetex, vec2(coord.x * 0.25, coord.y * 0.25 + frameTimeCounter) * invNoiseRes).r - 0.5);
	noise += (texture2D(noisetex, vec2(coord.x * 0.5,  coord.y * 0.5  + frameTimeCounter) * invNoiseRes).r - 0.5) * 0.5;
	noise += (texture2D(noisetex, vec2(coord.x,        coord.y        + frameTimeCounter) * invNoiseRes).r - 0.5) * 0.25;
	vec3 color = noise * lavaOverlayNoiseColor + lavaOverlayBaseColor;
	gl_FragData[0] = vec4(color, 1.0);
	return; //don't need to calculate anything else since the lava overlay covers the entire screen.
}