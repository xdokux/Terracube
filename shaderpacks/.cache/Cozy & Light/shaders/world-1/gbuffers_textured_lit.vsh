#version 330 compatibility

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

in vec3 vaPosition;
in vec3 vaNormal;

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;
out vec3 vertexPosition;
out float depth;
out vec3 normal;

#include "/world-1/lib_world-1.glsl"

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;
	vertexPosition = gl_Vertex.xyz;
	//depth = (gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex).z;
	depth = length(gl_ModelViewMatrix * gl_Vertex);
	normal = gl_Normal;
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;

	gl_Position = gl_ProjectionMatrix * viewPos;
}