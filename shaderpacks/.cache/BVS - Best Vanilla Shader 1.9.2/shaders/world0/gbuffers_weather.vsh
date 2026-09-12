#version 130

out vec2 TexCoords;
out vec4 Color;

void main() {
    gl_Position = ftransform();
	TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    Color = gl_Color;
}
