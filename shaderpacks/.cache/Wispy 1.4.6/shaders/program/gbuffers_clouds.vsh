#include "/lib/all_the_libs.glsl"
#include "/global/light_colors.vsh"

varying vec2 texcoord;
varying vec4 glcolor;
varying float cloudGradient;

void main() {
	gl_Position = ftransform();

	gl_Position.z = gl_Position.z * 0.9995 - 0.0001 * gl_Position.w;

	init_colors();

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	glcolor = gl_Color;

	cloudGradient = clamp((gl_Vertex.y + 0.5) / 4.0, 0.0, 1.0);

	#ifdef TAA_MODE
	#if TAA_MODE >= 2
	gl_Position.xy += taaJitter * gl_Position.w;
	#endif
	#endif
}
