#version 330 compatibility

#define RAY_SAMPLES 16 // [4 8 16 32 64]
#define RAY_STRENGTH 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

#include "/library/pad.glsl"
#include "/library/bluenoise.glsl"

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D colortex3;

uniform vec3 sunPosition;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform float viewWidth;
uniform float viewHeight;

uniform int isEyeInWater;

in vec2 texcoord;

/* RENDERTARGETS: 6 */
layout(location = 0) out vec4 color;

const int SAMPLES = RAY_SAMPLES;
const float DECAY = 0.97;
const float DENSITY = 0.7;
const float WEIGHT = 0.4;

void main() {
	if (RAY_STRENGTH == 0.0) return;
	vec3 sunDir = normalize(sunPosition);

	float facing = dot(sunDir, vec3(0.0, 0.0, -1.0));
	float viewFade = smoothstep(cos(radians(90.0)), cos(radians(60.0)), facing);

	if (viewFade <= 0.0) {
		color = vec4(0.0, 0.0, 0.0, 1.0);
		return;
	}

	vec4 clipSunPos = gbufferProjection * vec4(sunPosition, 1.0);
	vec2 sunScreenPos = (clipSunPos.xy / abs(clipSunPos.w)) * 0.5 + 0.5;

	vec2 deltaTexCoord = (texcoord - sunScreenPos) * DENSITY / float(SAMPLES);

	ivec2 screenCoord = ivec2(gl_FragCoord.xy);
	float noise = getNoise(uvec2(screenCoord));

	vec2 sampleCoord = texcoord - deltaTexCoord * noise;
	float illuminationDecay = 1.0;
	float accum = 0.0;

	for (int i = 0; i < SAMPLES; i++) {
		sampleCoord -= deltaTexCoord;

		float mask = texture(colortex3, sampleCoord).r;
		float depth = texture(depthtex0, sampleCoord).r;

		if (abs(mask - 5.0) < 0.1 || abs(mask - 11.0) < 0.1) {
			depth = texture(depthtex1, sampleCoord).r;
		}

		float sky = (depth == 1.0) ? 1.0 : 0.0;

		accum += sky * illuminationDecay * WEIGHT;
		illuminationDecay *= DECAY;
	}

	float maxAccum = WEIGHT * (1.0 - pow(DECAY, float(SAMPLES))) / (1.0 - DECAY);
	accum /= maxAccum;

	vec3 ndc = vec3(texcoord * 2.0 - 1.0, 1.0);
	vec3 pixelDir = normalize(projectAndDivide(gbufferProjectionInverse, ndc));

	float angleDist = 1.0 - dot(pixelDir, sunDir);

	float edgeFade = 1.0 - smoothstep(0.0, 1.0, angleDist);
	edgeFade = pow(edgeFade, 10.0);

	vec3 rayColor = vec3(3.0, 1.0, 2.0) * accum * edgeFade * viewFade * 0.2 * RAY_STRENGTH * 0.4;

	if (isEyeInWater == 1) {
		rayColor *= vec3(0.1, 0.3, 0.7) * 5.0;
	}

	color = vec4(rayColor, 1.0);
}