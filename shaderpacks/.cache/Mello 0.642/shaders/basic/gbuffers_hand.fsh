uniform sampler2D lightmap;
uniform sampler2D gtexture;

in vec2 lmcoord;
in vec2 texcoord;
in vec3 normal;
in vec4 glcolor;

/* RENDERTARGETS: 0,1,2,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 packLight;
layout(location = 2) out vec4 packNormal;
layout(location = 3) out vec4 packMask;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	if (color.a < 0.1) discard;
	
	packLight = vec4(lmcoord, 0.0, 1.0);
	packNormal = vec4(normal * 0.5 + 0.5, 1.0);
	packMask = vec4(0.0, 0.0, 0.0, 1.0);
}