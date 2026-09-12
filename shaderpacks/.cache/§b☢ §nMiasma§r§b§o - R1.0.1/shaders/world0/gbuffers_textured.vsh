#version 130

#include "/settings.glsl"

uniform float viewWidth, viewHeight;
#include "/lib/jitter.glsl"

in vec3 mc_Entity;

out vec2 lmcoord;
out vec2 texcoord;
out vec2 LightmapCoords;
out vec4 glcolor;
out vec3 viewPos;
out float blockId;
out vec3 Normal;
out vec3 viewSpaceGeoNormal;

void main() {
	blockId = mc_Entity.x;

	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;

	viewPos = vec3(gl_ModelViewMatrix * gl_Vertex);
	
	Normal = gl_Normal;
	viewSpaceGeoNormal = gl_NormalMatrix * gl_Normal;

	#if TYPE_AA == 1
	gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
	#endif
}
