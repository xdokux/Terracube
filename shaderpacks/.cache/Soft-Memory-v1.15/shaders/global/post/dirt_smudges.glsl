vec3 dirt_smudges(vec2 uv,float vDotL) {
    vec3 color = vec3(0.0);
    float scale = 1.0; // Adjust the scale for more or fewer smudges
    float intensity = 1.05; // Adjust the intensity of the smudges

    // Generate a noise value based on the UV coordinates
    float noiseValue = rand(uv * scale);

    // Create smudges based on the noise value
    if (noiseValue > 0.8) {
        color += vec3(0.1, 0.1, 0.1) * intensity; // Light smudge
    } else if (noiseValue > 0.6) {
        color += vec3(0.2, 0.2, 0.2) * intensity; // Medium smudge
    } else if (noiseValue > 0.4) {
        color += vec3(0.3, 0.3, 0.3) * intensity; // Dark smudge
    }

    return color * vDotL; // Modulate by the dot product of the view and light direction for a more natural effect
    
}