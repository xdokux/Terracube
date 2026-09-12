// composite.fsh
// Whole-screen finishing pass: filmic tonemap so the shadow-mapped lighting
// in gbuffers_terrain/water doesn't clip, plus a light contrast/saturation
// lift and a subtle vignette. Nothing here reads depth or does anything
// scene-aware - that's deliberate for v1, keeps it cheap and easy to verify.

varying vec2 texcoord;

uniform sampler2D colortex0;

const float CONTRAST = 1.05;
const float SATURATION = 1.05;
const float EXPOSURE = 1.0;
const float VIGNETTE_STRENGTH = 0.35;

/* DRAWBUFFERS:0 */

vec3 tonemapReinhard(vec3 color) {
	return color / (color + vec3(1.0));
}

void main() {
	vec3 color = texture2D(colortex0, texcoord).rgb * EXPOSURE;

	color = tonemapReinhard(color);

	// contrast
	color = (color - 0.5) * CONTRAST + 0.5;

	// saturation
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, SATURATION);

	// vignette
	vec2 uv = texcoord - 0.5;
	float vig = 1.0 - dot(uv, uv) * VIGNETTE_STRENGTH;
	color *= vig;

	gl_FragData[0] = vec4(clamp(color, 0.0, 1.0), 1.0);
}
