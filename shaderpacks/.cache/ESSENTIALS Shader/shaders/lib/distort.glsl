const int shadowMapResolution = 512;

float distortionFactor(vec2 shadowPos) {
    return length(shadowPos) * 0.9 + 0.1;
}

vec3 distort(vec3 shadowPos) {
    float factor = distortionFactor(shadowPos.xy);
    shadowPos.xy /= factor;
    shadowPos.z *= 0.4;
    return shadowPos;
}