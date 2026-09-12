vec3 calcFogColor(vec3 pos) {
	return mix(skyColor, fogColor, fogify(max(dot(pos, gbufferModelView[1].xyz), 0.0), TF_HORIZON_HEIGHT));
}