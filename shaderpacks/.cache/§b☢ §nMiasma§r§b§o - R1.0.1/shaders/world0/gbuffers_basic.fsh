#version 130

uniform sampler2D lightmap;
uniform sampler2D texture;

uniform float far, near;
uniform vec3 fogColor;

in vec2 lmcoord;
in vec2 texcoord;
in vec3 viewPos;
in vec4 glcolor;

in vec3 viewSpaceGeoNormal;

void main() {
	vec4 color = glcolor;
	color *= texture2D(lightmap, lmcoord);

	/* DRAWBUFFERS:03 */
	gl_FragData[0] = color;
	gl_FragData[1] = vec4(1, 0, 0, 1);
}
