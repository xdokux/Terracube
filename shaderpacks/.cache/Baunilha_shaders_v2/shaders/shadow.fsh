#version 430 compatibility
// Vanilla Shader - Iris Version by racxusdev - racxudev.blogspot.com
uniform sampler2D gtexture;
in vec2 texcoord;
in vec4 glcolor;
layout(location = 0) out vec4 color;
void main() {
	color = texture(gtexture, texcoord) * glcolor;
	if(color.a < 0.1){
		discard;
	}
}
