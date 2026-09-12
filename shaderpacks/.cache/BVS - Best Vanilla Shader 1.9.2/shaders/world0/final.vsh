#version 130

//Shader by LoLip_p

out vec2 TexCoords;

void main() {
    gl_Position = ftransform();
	TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
