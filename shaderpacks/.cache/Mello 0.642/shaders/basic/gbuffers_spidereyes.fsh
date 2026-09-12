uniform sampler2D gtexture;
uniform int entityId;

in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	color = texture(gtexture, texcoord) * glcolor * 2.0;
	if (color.a < 0.1) discard;

	if (entityId == 27.0) color.rgb *= vec3(2.0, 1.0, 3.0) * 1.5;
	if (entityId == 28.0 || entityId == 29.0) color.rgb *= 4.0;
}