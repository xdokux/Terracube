#version 330 compatibility

#include "/library/pad.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;
uniform float far;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	color = texture(colortex0, texcoord);
	float depth = texture(depthtex0, texcoord).r;

	vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);

	float dist = length(viewPos) / far;
	float fogFactor = exp(-3 * (1.0 - dist));

	color.rgb = mix(color.rgb, vec3(2.0, 0.5, 0.3), clamp(fogFactor, 0.0, 1.0));
}