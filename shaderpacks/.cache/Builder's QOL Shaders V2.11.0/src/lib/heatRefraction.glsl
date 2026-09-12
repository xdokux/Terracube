vec2 heatRefractionOffset() {
	if (HEAT_REFRACTION == 0.0) {
		return vec2(0.0);
	}
	else {
		vec2 coord = gl_FragCoord.xy * invNoiseRes * heatRefractionScale;
		float time = frameTimeCounter * heatRefractionSpeed;
		coord.y -= time;
		vec2 offset = vec2(-1.5);
		offset += texture2D(noisetex, coord).rb;
		offset += texture2D(noisetex, vec2(coord.x - time, coord.y)).rb;
		offset += texture2D(noisetex, vec2(coord.x + time, coord.y)).rb;
		return offset * vec2(pixelSizeX, pixelSizeY);
	}
}