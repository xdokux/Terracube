#version 120
/* 高光 */
uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform float viewWidth;
uniform float viewHeight;

const vec3 HIGHLIGHT_COLOR = vec3(1.0);
const float HIGHLIGHT_THRESHOLD = 0.7;
const float HIGHLIGHT_STRENGTH = 0.9;
const int SAMPLE_RADIUS = 3;
const float EDGE_SOFTNESS = 0.1;

float calculateHighlight(vec2 texcoord) {
	float highlight = 0.0;
	vec2 pixelSize = 1.0 / vec2(viewWidth, viewHeight);

	for(int x = -SAMPLE_RADIUS; x <= SAMPLE_RADIUS; x++) {
		for(int y = -SAMPLE_RADIUS; y <= SAMPLE_RADIUS; y++) {
			vec2 offset = vec2(x, y) * pixelSize;
			vec3 sampleColor = texture2D(colortex0, texcoord + offset).rgb;
			float luminance = dot(sampleColor, vec3(0.2126, 0.7152, 0.0722));
			highlight += smoothstep(HIGHLIGHT_THRESHOLD - EDGE_SOFTNESS,
			HIGHLIGHT_THRESHOLD + EDGE_SOFTNESS,
			luminance);
		}
	}
	int totalSamples = (SAMPLE_RADIUS*2+1)*(SAMPLE_RADIUS*2+1);
	highlight /= float(totalSamples);
	return pow(highlight, 1.0/HIGHLIGHT_STRENGTH);
}
void main() {
	vec2 texcoord = gl_TexCoord[0].st;
	vec3 color = texture2D(colortex0, texcoord).rgb;
	float highlightMask = calculateHighlight(texcoord);
	vec3 finalColor = mix(color, HIGHLIGHT_COLOR, highlightMask);
	gl_FragColor = vec4(finalColor, 1.0);
}