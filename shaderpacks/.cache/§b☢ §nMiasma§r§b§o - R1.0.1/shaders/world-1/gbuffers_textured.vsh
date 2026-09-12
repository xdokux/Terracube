#version 130

#include "/settings.glsl"

uniform float viewWidth, viewHeight;
#include "/lib/jitter.glsl"

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;
out vec3 viewPos;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;

	viewPos = vec3(gl_ModelViewMatrix * gl_Vertex);

	#if TYPE_AA == 1
	gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
	#endif
}
