uniform sampler2D lightmap;
uniform sampler2D gtexture;
uniform float sunAngle;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0,1,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 packLight;
layout(location = 2) out vec4 packMask;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	color.rgb = vec3(1.0 - smoothstep(0.4, 0.6, sunAngle) * (1.0 - smoothstep(0.9, 1.0, sunAngle)));
	color.a *= 0.2;
	if (color.a < 0.1) discard;
	
	packLight = vec4(lmcoord, 0.0, 1.0);
	packMask = vec4(14.0, 1.0, 1.0, 1.0);
}