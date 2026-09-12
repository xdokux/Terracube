#version 330 compatibility

#include "/library/time.glsl"
#include "/library/pad.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex1;

uniform mat4 gbufferProjectionInverse;
uniform float far;
uniform int isEyeInWater;
uniform float rainStrength;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	color = texture(colortex0, texcoord);
	float depth = texture(depthtex1, texcoord).r;
	if (depth == 1.0) return;

	vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);

	calculateTimeBlend();

    float dist = length(viewPos) / far;

    vec3 fogColor = getSkyHorizonColor();
    float fogFactor = exp(-5.0 * (1.0 - dist));

	if (isEyeInWater == 1) {
        fogColor = vec3(0.0, 0.7, 1.0) * fogColor * 0.5;
        fogFactor = 1.0 - exp(-5.0 * dist);
    }
    if (isEyeInWater == 2) {
        fogColor = vec3(1.4, 0.35, 0.0) * 2.0;
        fogFactor = 1.0 - exp(-20.0 * dist);
    }
    else if (isEyeInWater == 3) {
        fogColor = vec3(1.0, 1.0, 1.0) * fogColor;
        fogFactor = 1.0 - exp(-100.0 * dist);
    }

    color.rgb = mix(color.rgb, (fogColor * pow(1.0 - rainStrength * 0.3, 3.0)), clamp(fogFactor, 0.0, 1.0));
}