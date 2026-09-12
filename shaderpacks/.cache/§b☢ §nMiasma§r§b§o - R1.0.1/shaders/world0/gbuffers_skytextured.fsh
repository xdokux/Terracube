#version 130

uniform sampler2D texture;
uniform float rainStrength;

in vec2 TexCoords;

void main() {
    vec4 color = texture2D(texture, TexCoords);
    color.a *= 1.0 - rainStrength;

	color.rgb *= vec3(0.5, 0.3, 0.7);

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = color;
}
