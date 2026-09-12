#version 330 compatibility

#include "/library/pad.glsl"
#include "/library/time.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform float rainStrength;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    color = texture(colortex0, texcoord);
    if (texture(depthtex0, texcoord).r != 1.0) return;

    calculateTimeBlend();

	vec4 ndcPos = vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
	vec4 tmp = gbufferProjectionInverse * ndcPos;
	vec3 viewDir = normalize(tmp.xyz / tmp.w);
	vec3 worldDir = normalize((gbufferModelViewInverse * vec4(viewDir, 0.0)).xyz);

	float fog = 1.0 - smoothstep(0.0, 0.25, worldDir.y);

	color.rgb = mix(color.rgb, (getSkyHorizonColor() * pow(1.0 - rainStrength * 0.3, 3.0)), fog);
}