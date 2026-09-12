#version 130

uniform sampler2D texture;

in vec2 texcoord;
in vec4 color;

void main() {
	/* DRAWBUFFERS:03 */
	gl_FragData[0] = texture2D(texture, texcoord) * color;
	gl_FragData[1] = vec4(1, 1, 1, 1);
}