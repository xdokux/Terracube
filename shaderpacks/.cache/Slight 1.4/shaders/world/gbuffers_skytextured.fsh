#version 330 compatibility

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;

layout(location = 0) out vec4 color;

void main() {
	color = pow(texture(gtexture, texcoord),vec4(3.0)) * glcolor * 5.0;
	if (color.a < 0.1) discard;
}