#version 330 compatibility

uniform sampler2D depthtex0;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex3;
uniform float nightVision;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

const vec3 blocklightColor = vec3(1.0, 0.6, 0.4) * 0.7;
const vec3 ambientColor = vec3(0.1);

void main() {
	color = texture(colortex0, texcoord);
	float depth = texture(depthtex0, texcoord).r;
	if (depth == 1.0) return;

	float mask = texture(colortex3, texcoord).r;
	if (!(abs(mask - 40.0) < 0.1 || abs(mask - 41.0) < 0.1)) return;

	vec2 lightmap = texture(colortex1, texcoord).rg - 0.04;
	lightmap = clamp(vec2(1.0), vec2(0.0), lightmap);

	float nightvis = nightVision;

	vec3 blocklight = lightmap.r * blocklightColor;
	vec3 ambient = ambientColor + vec3(0.2, 0.22, 0.25) * nightvis;

	color.rgb *= blocklight + ambient;
}