// https://github.com/Experience-Monks/glsl-fast-gaussian-blur
float noise(vec2 Coords) {
    float color = texture2D(noisetex, Coords/(noiseTextureResolution*0.5)).x * 0.2;
	color += texture2D(noisetex, Coords/(noiseTextureResolution*1)).x * 0.3;
	color += texture2D(noisetex, Coords/(noiseTextureResolution*2)).x * 0.5;
    return color;
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float swirl_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 natural_hash(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float natural_perlin(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    // Smooth cubic interpolation (removes sharp edges)
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = dot(natural_hash(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
    float b = dot(natural_hash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float c = dot(natural_hash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
    float d = dot(natural_hash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 3 Octaves is enough for water ripples (keeps fps high)
float swirl_fbm(vec2 p) {
    float value = 1.0; 
    float amplitude = 130.5; 
    
    for (int i = 0; i < 3; i++) {
        // (noise * 2.0 - 1.0) centers the noise perfectly between -1.0 and 1.0
        value += amplitude * (swirl_noise(p) * 2.0 - 1.0);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}
vec2 noise_normal(vec2 Coords) {
	vec2 color = (texture2D(noisetex, Coords/(noiseTextureResolution*0.5)).yz * 2 - 1) * 0.2;
	color += (texture2D(noisetex, Coords/(noiseTextureResolution*1)).yz * 2 - 1) * 0.3;
	color += (texture2D(noisetex, Coords/(noiseTextureResolution*2)).yz * 2 - 1) * 0.5;
	return color;
}

vec2 noise_water(vec2 Coords) {

	#ifdef SWIRLED_WATER
   vec2 st = Coords / (WATER_NORMAL_SIZE * 0.8); 
        float t = frameTimeCounter * WATER_NORMAL_SPEED * 1.5;


        float eps = 0.001; 

        // 3. Generate the natural water height map
        vec2 pBase = st;
        vec2 pX = st + vec2(eps, 0.0);
        vec2 pY = st + vec2(0.0, eps);

        // Layer 1: Broad, lazy waves drifting
        float h  = natural_perlin(pBase * 1.5 + t * 0.4);
        float hx = natural_perlin(pX * 1.5 + t * 0.4);
        float hy = natural_perlin(pY * 1.5 + t * 0.4);

        // Layer 2: Smaller wind ripples
        h  += natural_perlin(pBase * 3.0 - t * 0.6 + vec2(2.3, 1.5)) * 0.4;
        hx += natural_perlin(pX * 3.0 - t * 0.6 + vec2(2.3, 1.5)) * 0.4;
        hy += natural_perlin(pY * 3.0 - t * 0.6 + vec2(2.3, 1.5)) * 0.4;

        // 4. Convert heights into slopes
        vec2 normalOffset = vec2(hx - h, hy - h) * 10.0;
        
        vec2 finalNoise = normalOffset * (WATER_NORMAL_STRENGTH * 1.8);

        return finalNoise;
	#else
	    Coords /= WATER_NORMAL_SIZE;

    vec2 color = (texture2D(watertex, (Coords+frameTimeCounter*0.2*(WATER_NORMAL_SPEED / 3))/24).yz * 2 - 1) * 0.05;

    return color * WATER_NORMAL_STRENGTH;
	#endif
}

float fbm_clouds(vec2 x, int detail) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100);
	// Rotate to reduce axial bias
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.50));
	for (int i = 0; i < detail; ++i) {
		v += a * noise(x);
		x = rot * x * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

vec2 fbm_clouds_normal(vec2 x, int detail) {
	vec2 v = vec2(0.0);
	float a = 0.5;
	vec2 shift = vec2(100);
	// Rotate to reduce axial bias
	mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.50));
	for (int i = 0; i < detail; ++i) {
		v += a * noise_normal(x);
		x = rot * x * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

float fbm_fast(vec2 x, int detail) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100);
	// Rotate to reduce axial bias
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.50));
	for (int i = 0; i < detail; ++i) {
		v += a * texture2D(noisetex, x/noiseTextureResolution).x;
		x = rot * x * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

// https://www.shadertoy.com/view/4ssfWM
float bayer8(vec2 a) {
    uvec2 b = uvec2(a);
    uint c = (b.x^b.y)<<1u;
    return float(
        ((c&8u|b.y&4u)>>2u)|
        ((c&4u|b.y&2u)<<1u)|
        ((c&2u|b.y&1u)<<4u)  //15 ops
    )/8./8.;
}

float ign(vec2 Pos, const bool Animate) {
	if(Animate) {
    	float FrameMod = frameCounter % 64;
    	Pos += 5.588238f * FrameMod;
	}

    return fract(52.9829189 * fract(0.06711056 * Pos.x + 0.00583715 * Pos.y));
}

float dither(vec2 Pos) {
	// Interleaved gradient noise
    #if TAA_MODE != 0

    return ign(Pos, true);
	#endif
	// Use bayer dither when TAA is disabled because it's more visually pleasing
	return bayer8(Pos);
}
