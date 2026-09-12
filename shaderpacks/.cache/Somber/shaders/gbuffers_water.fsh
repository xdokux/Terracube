#version 330 compatibility

uniform sampler2D lightmap;
uniform sampler2D gtexture;

uniform float alphaTestRef = 0.1;

#define noWaterTransparency
#define waterBlueness 2.0 // [1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.8 1.9 20.0]

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	color *= pow(texture(lightmap, lmcoord), vec4(4.0));
	color.b *= waterBlueness;
	#ifdef noWaterTransparency
		color.a = 1.0;
	#endif
	if (color.a < alphaTestRef) {
		discard;
	}
}