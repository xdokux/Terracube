#version 130

#include "/settings.glsl"

uniform float viewWidth, viewHeight;
#include "/lib/jitter.glsl"

out vec2 TexCoords;

void main() {
	gl_Position = ftransform();
	TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	#if TYPE_AA == 1
	//gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
	#endif
}
