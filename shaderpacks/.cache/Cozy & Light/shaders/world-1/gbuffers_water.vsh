#version 330 compatibility

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform float frameTimeCounter;

in vec3 vaPosition;
in vec3 vaNormal;
in vec2 mc_Entity;

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;
out vec3 vertexPosition;
out vec3 worldPosition;
out float depth;
out vec3 normal;
out float blockId;

#include "/world-1/lib_world-1.glsl"

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;
	vertexPosition = gl_Vertex.xyz;
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
	worldPosition = ViewPosToWorldPos(viewPos.xyz);
	//depth = (gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex).z;
	depth = length(viewPos.xyz);
	normal = gl_Normal;
	blockId = mc_Entity.x;

	gl_Position = gl_ProjectionMatrix * vec4(WorldPosToViewPos(worldPosition), 1.0);
}