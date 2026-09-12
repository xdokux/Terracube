#version 430 compatibility
// Vanilla Shader - Iris Version by racxusdev - racxudev.blogspot.com
uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform float viewWidth;
uniform float viewHeight;
in vec2 texcoord;
layout(location = 0) out vec4 color;

#define FXAA_REDUCE_MIN   (1.0/128.0)
#define FXAA_REDUCE_MUL   (1.0/8.0)
#define FXAA_SPAN_MAX     (8.0)
#define FXAA_CONTRAST     0.0312

vec4 fxaa(sampler2D tex, vec2 uv) {
	vec2 texelSiz = 1.0 / vec2(viewWidth, viewHeight);
	vec3 rgbM = texture(tex, uv).rgb;
	vec3 rgbNW = texture(tex, uv + vec2(-1.0, -1.0) * texelSiz).rgb;
	vec3 rgbNE = texture(tex, uv + vec2( 1.0, -1.0) * texelSiz).rgb;
	vec3 rgbSW = texture(tex, uv + vec2(-1.0,  1.0) * texelSiz).rgb;
	vec3 rgbSE = texture(tex, uv + vec2( 1.0,  1.0) * texelSiz).rgb;
	const vec3 lumaW = vec3(0.2126, 0.7152, 0.0722);
	float lumaNW = dot(rgbNW, lumaW);
	float lumaNE = dot(rgbNE, lumaW);
	float lumaSW = dot(rgbSW, lumaW);
	float lumaSE = dot(rgbSE, lumaW);
	float lumaM  = dot(rgbM,  lumaW);
	float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
	float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
	// Skip non-edge pixels, preserva nitidez em áreas planas
	float contrast = lumaMax - lumaMin;
	if (contrast < FXAA_CONTRAST) return vec4(rgbM, 1.0);
	vec2 dir = vec2(-((lumaNW + lumaNE) - (lumaSW + lumaSE)),
					 ((lumaNW + lumaSW) - (lumaNE + lumaSE)));
	float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN);
	float rcpDir = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
	dir = min(vec2(FXAA_SPAN_MAX), max(vec2(-FXAA_SPAN_MAX), dir * rcpDir)) * texelSiz;
	vec3 rgbA = 0.5 * (texture(tex, uv + dir * (1.0/3.0 - 0.5)).rgb + texture(tex, uv + dir * (2.0/3.0 - 0.5)).rgb);
	vec3 rgbB = rgbA * 0.5 + 0.25 * (texture(tex, uv + dir * -0.5).rgb + texture(tex, uv + dir * 0.5).rgb);
	float lumaB = dot(rgbB, lumaW);
	if ((lumaB < lumaMin) || (lumaB > lumaMax)) return vec4(rgbA, 1.0);
	return vec4(rgbB, 1.0);
}

vec3 bloom(sampler2D tex, vec2 uv) {
	vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
	float threshold = 0.6;
	vec3 blur = vec3(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			vec2 offset = vec2(x, y) * texel * 2.0;
			float weight = exp(-float(x * x + y * y) * 0.3);
			blur += max(texture(tex, uv + offset).rgb - threshold, 0.0) * weight;
			total += weight;
		}
	}
	return blur / max(total, 0.001);
}

void main() {
	color = fxaa(colortex0, texcoord);
	float depth = texture(depthtex0, texcoord).r;
	float depthMask = 1.0 - smoothstep(0.92, 1.0, depth);
	color.rgb += bloom(colortex0, texcoord) * 0.3 * depthMask;
	color.rgb = (color.rgb * (2.51 * color.rgb + 0.03)) / (color.rgb * (2.43 * color.rgb + 0.59) + 0.14);
	color.rgb = pow(color.rgb, vec3(1.0 / 2.2));
}
