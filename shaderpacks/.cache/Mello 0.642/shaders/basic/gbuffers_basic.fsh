uniform sampler2D lightmap;

in vec2 lmcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	color = glcolor;
	if (color.a < 0.1) discard;
}