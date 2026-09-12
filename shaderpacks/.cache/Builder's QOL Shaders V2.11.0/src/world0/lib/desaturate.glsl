float desaturationAmount = mix(night * DESATURATE_NIGHT, 1.0, rainStrength * DESATURATE_RAIN);
if (desaturationAmount > 0.001) {
	desaturationAmount *= 1.0 - max(blocklight, heldlight);
	float average = dot(color.rgb, vec3(0.25, 0.5, 0.25));
	color.rgb = mix(color.rgb, vec3(average), desaturationAmount);
}