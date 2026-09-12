#include "/lib/all_the_libs.glsl"

#include "/global/lighting.vsh"

void main() {
	#ifdef ROUND_SUN
		gl_Position = vec4(-1);
	#else
		gl_Position = ftransform();
		texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
		#if TAA_MODE >= 2
		gl_Position.xy += taaJitter * gl_Position.w;
		#endif
	#endif
}
