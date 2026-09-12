#version 330 compatibility

uniform sampler2D gtexture;

in float mask;
in vec2 lmcoord;
in vec2 texcoord;
in vec3 normal;
in vec4 glcolor;
in vec3 viewPos;

const vec3 blocklightColor = vec3(1.0, 0.6, 0.25);
const vec3 ambientColor = vec3(0.6, 0.4, 0.4);

/* RENDERTARGETS: 0,1,2,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 packLight;
layout(location = 2) out vec4 packNormal;
layout(location = 3) out vec4 packMask;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	if (color.a < 0.1) discard;

	if (abs(mask - 5.0) < 0.1) color = vec4(1.0, 1.0, 1.0, 0.5);

	vec3 blocklight = lmcoord.r * blocklightColor;
	vec3 ambient = ambientColor;

	color.rgb *= blocklight + ambient;
	packLight = vec4(lmcoord, 0.0, 1.0);
	packNormal = vec4(normal * 0.5 + 0.5, 1.0);
	packMask = vec4(mask, 0.0, 0.0, 1.0);
}