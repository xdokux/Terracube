#version 430 compatibility
// Vanilla Shader - Iris Version by racxusdev - racxudev.blogspot.com
uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform float viewWidth;
uniform float viewHeight;
in vec2 texcoord;
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;
#include "/lib/settings.glsl"
const vec3 SUN_COLOR = vec3(1.0, 0.82, 0.5);
const vec3 MOON_COLOR = vec3(0.3, 0.45, 0.65);
void main() {
	vec3 albedo = texture(colortex0, texcoord).rgb;
	float depth = texture(depthtex0, texcoord).r;
	vec3 sunVec = normalize(sunPosition);
	vec3 worldSunVec = mat3(gbufferModelViewInverse) * sunVec;
	float nightFactor = clamp(-worldSunVec.y, 0.0, 1.0);
	vec3 lightPos = mix(sunPosition, shadowLightPosition, nightFactor);
	vec3 lightColor = mix(SUN_COLOR, MOON_COLOR, nightFactor);
	float intensity = mix(GOD_RAY_INTENSITY, GOD_RAY_INTENSITY * MOON_RAY_FACTOR, nightFactor);
	vec4 lightClip = gbufferProjection * vec4(lightPos, 1.0);
	vec3 lightNDC = lightClip.xyz / lightClip.w;
	vec2 lightScreen = lightNDC.xy * 0.5 + 0.5;
	bool lightOnScreen = (lightClip.w > 0.0 &&
		lightNDC.x >= -1.0 && lightNDC.x <= 1.0 &&
		lightNDC.y >= -1.0 && lightNDC.y <= 1.0 &&
		lightNDC.z >= -1.0 && lightNDC.z <= 1.0);
	float godRays = 0.0;
	if (lightOnScreen) {
		vec2 rayDir = lightScreen - texcoord;
		vec2 screenPos = texcoord * vec2(viewWidth, viewHeight);
		float dither = fract(sin(dot(screenPos, vec2(12.9898, 78.233))) * 43758.5453);
		float totalWeight = 0.0;
		for (int i = 0; i < GOD_RAY_SAMPLES; i++) {
			float t = (float(i) + dither) / float(GOD_RAY_SAMPLES);
			vec2 sampleUV = texcoord + rayDir * t * 0.92;
			float sampleDepth = texture(depthtex0, sampleUV).r;
			float weight = 1.0 - t;
			if (sampleDepth >= 1.0) {
				godRays += weight;
			}
			totalWeight += weight;
		}
		godRays = (godRays / max(totalWeight, 0.001)) * intensity;
	}
	color.rgb = albedo + godRays * lightColor;
}
