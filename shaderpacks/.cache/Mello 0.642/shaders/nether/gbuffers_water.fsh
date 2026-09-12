#version 330 compatibility

#include "/library/pad.glsl"

uniform sampler2D gtexture;

in float mask;
in vec2 lmcoord;
in vec2 texcoord;
in vec3 normal;
in vec4 glcolor;

const vec3 blocklightColor = vec3(1.0, 0.6, 0.4) * 0.7;
const vec3 ambientColor = vec3(0.1);

uniform float nightVision;

/* RENDERTARGETS: 0,1,2,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 packLight;
layout(location = 2) out vec4 packNormal;
layout(location = 3) out vec4 packMask;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	if (abs(mask - 11.0) > 0.1 && color.a < 0.1) discard;

	if (abs(mask - 5.0) < 0.1) color = vec4(1.0, 1.0, 1.0, 0.2);
	if (abs(mask - 8.0) < 0.1) color.rgb *= vec3(2.0, 1.0, 5.0) * 0.5;

	float nightvis = nightVision;

	vec2 lm = lmcoord - vec2(0.04);
	lm = clamp(vec2(1.0), vec2(0.0), lm);

	vec3 blocklight = lm.r * blocklightColor;
	vec3 ambient = ambientColor + vec3(0.2, 0.22, 0.25) * nightvis;

	color.rgb *= blocklight + ambient;

	packLight = vec4(lm, 0.0, 1.0);
	packNormal = vec4(normalize(normal) * 0.5 + 0.5, 1.0);
	packMask = vec4(mask, 0.0, 0.0, 1.0);
}