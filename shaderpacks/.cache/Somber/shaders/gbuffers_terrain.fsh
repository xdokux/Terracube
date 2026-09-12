#version 330 compatibility

uniform sampler2D lightmap;
uniform sampler2D gtexture;

#define oldFoliageGreen
#define foliageGreenAmount 1.6 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {

    vec4 foliage = glcolor;

	#ifdef oldFoliageGreen 
		bool tinted = foliage.r == foliage.g && foliage.r == foliage.b;
		if (!tinted) {
			foliage.g *= foliageGreenAmount;
		}	
	#endif

	color = texture(gtexture, texcoord) * foliage;
	color *= pow(texture(lightmap, lmcoord), vec4(4.0));
	if (color.a < alphaTestRef) {
		discard;
	}
}
