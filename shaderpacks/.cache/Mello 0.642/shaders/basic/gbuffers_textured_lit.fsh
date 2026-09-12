uniform sampler2D lightmap;
uniform sampler2D gtexture;

in vec2 lmcoord;
in vec2 texcoord;
in vec3 normal;
in vec4 glcolor;

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 packLight;
layout(location = 2) out vec4 packNormal;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	if (color.a < 0.1) discard;
	
	packLight = vec4(lmcoord, 0.0, 1.0);
	packNormal = vec4(normal * 0.5 + 0.5, 1.0);
	color.rgb *= mix(1.0, 5.0, smoothstep(0.9, 1.0, lmcoord.x));
}