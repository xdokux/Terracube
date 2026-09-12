if (DESATURATE_END > 0.0) {
	float desatAmt = DESATURATE_END * (1.0 - max(blocklight, heldlight));
	float average = dot(color.rgb, vec3(0.25, 0.5, 0.25));
	color.rgb = mix(color.rgb, vec3(average), desatAmt);
}