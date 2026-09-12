#version 120

uniform float viewHeight;
uniform float viewWidth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform vec3 fogColor;
uniform vec3 skyColor;

varying vec4 starData; // rgb = star color, a = flag for whether this pixel is a star

float fogify(float x, float w) {
	return w / (x * x + w);
}

vec3 calcSkyColor(vec3 pos) {
	float upDot = dot(pos, gbufferModelView[1].xyz);

	// Check if in Overworld based on fogColor (works reliably)
	bool isOverworld = (fogColor.r > 0.3 && fogColor.g > 0.5 && fogColor.b > 0.3);

	// Natural cyanish blue tint, 2x boost
	vec3 cyanBlue = vec3(0.3, 0.6, 1.1); // 2x stronger than real sky

	// Clamp to keep it visually realistic
	cyanBlue = clamp(cyanBlue, 0.0, 1.0);

	// Choose custom sky only for Overworld
	vec3 baseSkyColor = isOverworld ? cyanBlue : skyColor;

	return mix(baseSkyColor, fogColor, fogify(max(upDot, 0.0), 0.25));
}

void main() {
	vec3 color;
	if (starData.a > 0.5) {
		color = starData.rgb;
	} else {
		vec4 pos = vec4(gl_FragCoord.xy / vec2(viewWidth, viewHeight) * 2.0 - 1.0, 1.0, 1.0);
		pos = gbufferProjectionInverse * pos;
		color = calcSkyColor(normalize(pos.xyz));
	}

	/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(color, 1.0); // gcolor
}
