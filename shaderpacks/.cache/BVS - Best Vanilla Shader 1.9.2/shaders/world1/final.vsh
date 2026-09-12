#version 130

//Shader by LoLip_p

varying vec2 TexCoords;

void main() {
    gl_Position = ftransform();
	TexCoords = gl_MultiTexCoord0.st;
}
