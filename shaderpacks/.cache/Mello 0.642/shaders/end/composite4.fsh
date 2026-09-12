#version 330 compatibility

#include "/library/time.glsl"
#include "/library/pad.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D colortex5;

uniform sampler2D depthtex0;
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
	float depth = texture(depthtex0, texcoord).r;
	if (depth == 1.0) return;

    float mask = texture(colortex3, texcoord).r;
    if (!(abs(mask - 5.0) < 0.1 || abs(mask - 8.0) < 0.1 || abs(mask - 9.0) < 0.1 || abs(mask - 11.0) < 0.1 || abs(mask - 29.0) < 0.1 || abs(mask - 40.0) < 0.1 || abs(mask - 3.0) < 0.1 || abs(mask - 36.0) < 0.1)) return;

	vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);

    float dist = length(viewPos) / far;

    vec3 fogColor = vec3(0.1, 0.01, 0.2);
    float fogFactor = exp(-5.0 * (1.0 - dist));

    if (isEyeInWater == 2) {
        fogColor = vec3(1.4, 0.35, 0.0) * 2.0;
        fogFactor = 1.0 - exp(-20.0 * dist);
    }
    else if (isEyeInWater == 3) {
        fogColor = vec3(1.0, 0.6, 1.0) * 0.5;
        fogFactor = 1.0 - exp(-100.0 * dist);
    }

    color.rgb += texture(colortex5, texcoord).rgb * 5.0;
    color.rgb = mix(color.rgb, fogColor, clamp(fogFactor, 0.0, 1.0));
}