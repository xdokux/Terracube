#version 330 compatibility

uniform sampler2D lightmap;
uniform sampler2D gtexture;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;

#include "/world-1/lib_world-1.glsl"

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor0;

void main() {
	vec4 color = texture(gtexture, texcoord) * glcolor;

	color.rgb = pow(color.rgb, vec3(2.2));

	color *= texture(lightmap, lmcoord);
	if (color.a < alphaTestRef) {
		discard;
	}

	color.rgb = pow(color.rgb, vec3(1.0/2.2));

	outColor0 = color;
	//outColor0 = vec4(1.0);
}