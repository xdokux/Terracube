#version 120
/* 阴影增强 */
uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform float viewWidth;
uniform float viewHeight;

const vec3 SHADOW_COLOR = vec3(0.0, 0.1, 0.1);
const float SHADOW_BRIGHTNESS = 1.8;
const float SHADOW_STRENGTH = 0.8;
const int SHADOW_SAMPLES = 2;
const float SHADOW_SOFTNESS = 0.1;
const float SHADOW_RADIUS = 5;

float calculateShadow(vec2 texcoord) {
	float shadow = 0.0;
	vec2 pixelSize = 1.0 / vec2(viewWidth, viewHeight);
	for(int x = -SHADOW_SAMPLES; x <= SHADOW_SAMPLES; x++) {
		for(int y = -SHADOW_SAMPLES; y <= SHADOW_SAMPLES; y++) {
			vec2 offset = vec2(x, y) * pixelSize * SHADOW_RADIUS;
			vec3 colorSample = texture2D(colortex0, texcoord + offset).rgb;
			float luminance = dot(colorSample, vec3(0.2126, 0.7152, 0.0722));
			shadow += smoothstep(0.2, 0.8, luminance);
		}
	}
	shadow /= float((SHADOW_SAMPLES*2+1)*(SHADOW_SAMPLES*2+1));
	shadow = pow(shadow, SHADOW_SOFTNESS);
	return mix(1.0, shadow, SHADOW_STRENGTH);
}

void main() {
	vec2 texcoord = gl_TexCoord[0].st;
	vec3 color = texture2D(colortex0, texcoord).rgb;
	float shadow = calculateShadow(texcoord);
	vec3 shadowTint = SHADOW_COLOR * SHADOW_BRIGHTNESS;
	color = mix(
	color * shadowTint,
	color,
	shadow
	);

	gl_FragColor = vec4(color, 1.0);
}
