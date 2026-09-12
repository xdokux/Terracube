vec3 DistortPosition(vec3 shadowClipPos){
    float distortionFactor = length(shadowClipPos.xy);
	distortionFactor += 0.1;
	shadowClipPos.xy /= distortionFactor;
	shadowClipPos.z *= 0.5;
	return shadowClipPos;
}