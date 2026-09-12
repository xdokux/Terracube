#version 130

out vec2 TexCoords;
out vec3 Normal;
out vec4 Color;
out vec2 LightmapCoords;

void main() {

    gl_Position = ftransform();
	TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	
    LightmapCoords = gl_MultiTexCoord1.xy;
    LightmapCoords = (LightmapCoords * 33.05f / 32.0f) - (1.05f / 32.0f);
	
	Normal = gl_NormalMatrix * gl_Normal;
    Color = gl_Color;
}
