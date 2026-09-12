const float shadowMapBias = 1.0 - 25.6 / shadowDistance;

float get_distort_factor(vec2 pos) {
    return length(pos.xy) * shadowMapBias + (1 - shadowMapBias);
}

vec3 distort(vec3 pos) {
    float factor = get_distort_factor(pos.xy);
    return vec3(pos.xy / factor, pos.z * 0.2);
}

vec3 undistort(vec3 pos) {
    float factor = get_distort_factor(pos.xy);
    return vec3(pos.xy * factor, pos.z / 0.2);
}

// Adapted from Complementary Shaders
// with Emin's explicit permission
// Helios: tuned bias to reduce peter-panning on flat ground at higher
// shadow resolutions, while still preventing acne on steep surfaces.
vec3 compute_bias(vec3 PlayerPos, vec3 WorldNormal, float NdotL, float Skylight) {
    float DistanceBias = pow(dot(PlayerPos, PlayerPos), 0.75);
    DistanceBias = 0.12 + 0.0008 * DistanceBias;
    // Slightly stronger normal-based bias when the surface is grazing-lit,
    // where acne is most likely to appear at high shadow map resolutions.
    float Grazing = pow(1.0 - max(NdotL, 0.0), 2.0);
    vec3 Bias = WorldNormal * DistanceBias * (2.0 - 0.95 * max(NdotL, 0)) * (1.0 + 0.35 * Grazing);

    #ifdef DIMENSION_OVERWORLD
        if (Skylight < 0.5 && isEyeInWater != 1) {
            vec3 EdgeFactor = 0.2 * (0.5 - fract(PlayerPos + cameraPosition + WorldNormal * 0.01));
            Bias += max(0.5 - Skylight, 0) * EdgeFactor;
        }
    #endif

    return Bias;
}
