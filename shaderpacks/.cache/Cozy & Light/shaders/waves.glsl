const float waves_amplitude = 0.4;

float getWaves(vec2 coords, int iterations)
{
    float PI = 3.14159265;

	// Sum together several octaves of sine waves

	// Starting values, these will change with each iteration
    float period = 4.0;
    float wavelength = 4.0;
    float direction = 1.0;
    float amplitude = 0.15;
    float offset = 0.0;

    float sum = 0.0;
	float sumOfAmps = 0.0;
    
    for(int i = 0; i < iterations; i++)
    {
        float xComponent = cos(direction);
        float yComponent = sin(direction);

        float wave = amplitude * sin(2.0*PI *(frameTimeCounter/period + (coords.x*xComponent + coords.y*yComponent)/wavelength + offset));
        
        sum += wave;
		sumOfAmps += amplitude;
        
		// Modify wave properties for next iteration
        period *= 0.98;
        wavelength *= 0.93;
        amplitude *= 0.87;
        direction += float(i) * 11.258912;
        offset += 13.237894;
    }
    
	// exp to get a better wave shape and to normalize wave to be from 0 to 1
	// - 0.4 to roughly center the wave vertically
    return exp(sum/sumOfAmps - 1.0) - 0.4;
}