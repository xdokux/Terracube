vec3 distortShadowClipPos(vec3 shadowClipPos){
    float distortionFactor = length(shadowClipPos.xy);
    distortionFactor += 0.2;

    shadowClipPos.xy /= distortionFactor;
    shadowClipPos.z *= 0.5;
    return shadowClipPos;
}