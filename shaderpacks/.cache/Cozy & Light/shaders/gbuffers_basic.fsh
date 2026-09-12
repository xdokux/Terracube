#version 330 compatibility

uniform sampler2D lightmap;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor0;

void main() {
	vec4 color = glcolor;

	color.rgb = pow(color.rgb, vec3(2.2));
	color *= pow(texture(lightmap, lmcoord), vec4(2.2));

	color *= texture(lightmap, lmcoord);
	if (color.a < alphaTestRef) {
		discard;
	}

	color.rgb = pow(color.rgb, vec3(1.0/2.2));

	outColor0 = color;
}