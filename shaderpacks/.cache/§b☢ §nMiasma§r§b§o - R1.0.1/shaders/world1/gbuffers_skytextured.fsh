#version 130

uniform sampler2D texture;
uniform float rainStrength;

in vec2 TexCoords;

void main() {
	vec4 color = texture2D(texture, TexCoords);
	color.a *= 1 - rainStrength;
	
	color.rgb *= 0.15;
	
	/* DRAWBUFFERS:0 */
	gl_FragData[0] = color;
}
