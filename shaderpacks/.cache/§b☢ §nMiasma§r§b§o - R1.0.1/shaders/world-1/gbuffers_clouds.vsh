#version 130

#include "/settings.glsl"

uniform float viewWidth, viewHeight;
#include "/lib/jitter.glsl"

out vec2 texcoord;
out vec4 color;
out vec3 viewPos;

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	color = gl_Color;
	gl_Position = ftransform();
	viewPos = vec3(gl_ModelViewMatrix * gl_Vertex);

	#if TYPE_AA == 1
	gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
	#endif
}
