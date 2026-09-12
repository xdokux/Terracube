// Optimized texture-based noise sampling
float noise(vec2 Coords) {
	return texture2D(noisetex, Coords / noiseTextureResolution).x;
}

// Optimized normal mapping noise
vec2 noise_normal(vec2 Coords) {
	return texture2D(noisetex, Coords / noiseTextureResolution).yz * 2.0 - 1.0;
}

// Optimized water normal calculation
vec2 noise_water(vec2 Coords) {
	Coords /= WATER_NORMAL_SIZE;
	vec2 color = (texture2D(noisetex, (Coords + frameTimeCounter * 0.2 * WATER_NORMAL_SPEED) / 24.0).yz * 2.0 - 1.0) * 0.05;
	color += (texture2D(noisetex, (Coords - frameTimeCounter * 0.8 * WATER_NORMAL_SPEED) / 64.0).yz * 2.0 - 1.0) * 0.1;
	return color * WATER_NORMAL_STRENGTH;
}

// Fractional Brownian Motion for cloud structures
float fbm_clouds(vec2 x, int detail) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	// Pre-calculated rotation matrix
	const mat2 rot = mat2(0.877, 0.479, -0.479, 0.877);

	int iterations = min(detail, 4);
	for (int i = 0; i < iterations; ++i) {
		v += a * texture2D(noisetex, x / noiseTextureResolution).x;
		x = rot * x * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

// Fractional Brownian Motion for cloud normals
vec2 fbm_clouds_normal(vec2 x, int detail) {
	vec2 v = vec2(0.0);
	float a = 0.5;
	vec2 shift = vec2(100.0);
	const mat2 rot = mat2(0.877, 0.479, -0.479, 0.877);

	int iterations = min(detail, 4);
	for (int i = 0; i < iterations; ++i) {
		v += a * (texture2D(noisetex, x / noiseTextureResolution).yz * 2.0 - 1.0);
		x = rot * x * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

// Simplified FBM
float fbm_fast(vec2 x, int detail) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	const mat2 rot = mat2(0.877, 0.479, -0.479, 0.877);

	int iterations = min(detail, 4);
	for (int i = 0; i < iterations; ++i) {
		v += a * texture2D(noisetex, x / noiseTextureResolution).x;
		x = rot * x * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

// Bayer 8x8 dither pattern
float bayer8(vec2 a) {
	uvec2 b = uvec2(a);
	uint c = (b.x^b.y)<<1u;
	return float(
		((c&8u|b.y&4u)>>2u)|
		((c&4u|b.y&2u)<<1u)|
		((c&2u|b.y&1u)<<4u)
	)/64.0;
}

// Interleaved Gradient Noise
float ign(vec2 Pos, const bool Animate) {
	if(Animate) {
		float FrameMod = float(frameCounter % 64);
		Pos += 5.588238 * FrameMod;
	}
	return fract(52.9829189 * fract(0.06711056 * Pos.x + 0.00583715 * Pos.y));
}

// Dithering selector
float dither(vec2 Pos) {
	#if TAA_MODE != 0
	return ign(Pos, true);
	#else
	return bayer8(Pos);
	#endif
}
