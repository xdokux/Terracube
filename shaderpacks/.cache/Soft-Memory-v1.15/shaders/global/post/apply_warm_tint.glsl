vec3 applyWarmTint(vec3 color, float strength) {
    vec3 warm = vec3(1.05, 1.02, 0.98); // slightly more R and G
    return mix(color, color * warm, strength);
}