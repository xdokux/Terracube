#version 130

varying vec2 TexCoords;
varying vec3 Normal;
varying vec4 Color;
varying vec2 LightmapCoords;

void main() {
    gl_Position = ftransform();
	TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	
    LightmapCoords = mat2(gl_TextureMatrix[1]) * gl_MultiTexCoord1.st;
    LightmapCoords = (LightmapCoords * 33.05f / 32.0f) - (1.05f / 32.0f);
	
    Normal = gl_NormalMatrix * gl_Normal;
    Color = gl_Color;
}
