uniform sampler2D lightmap;
uniform sampler2D gtexture;

in vec2 lmcoord;
in vec2 texcoord;
in vec3 normal;
in vec4 glcolor;

/* RENDERTARGETS: 0,1,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 packLight;
layout(location = 2) out vec4 packMask;

void main() {
	color = texture(gtexture, texcoord) * glcolor * 3.0;
	if (color.a < 0.5) discard;
	color.a = 1.0;
	
	packLight = vec4(lmcoord, 0.0, 1.0);
	packMask = vec4(14.0, 1.0, 1.0, 1.0);
}