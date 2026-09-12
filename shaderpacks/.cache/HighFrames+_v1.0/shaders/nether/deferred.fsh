#version 330 compatibility

/*
const int colortex0Format = RGB16F;
*/

/*
const int colortex1Format = R8;
*/

/*
const int colortex2Format = RGB8;
*/

/*
const int colortex3Format = R16F;
*/

/*
const int colortex4Format = RGBA8;
*/

uniform sampler2D depthtex1;

uniform sampler2D colortex0;
uniform sampler2D colortex1;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

const vec3 blocklightColor = vec3(1.0, 0.6, 0.25);
const vec3 ambientColor = vec3(0.6, 0.4, 0.4);

void main() {
	color = texture(colortex0, texcoord);
	float depth = texture(depthtex1, texcoord).r;
	if (depth == 1.0) return;

	vec2 lightmap = texture(colortex1, texcoord).rg;

	vec3 blocklight = lightmap.r * blocklightColor;
	vec3 ambient = ambientColor;

	color.rgb *= blocklight + ambient;
}