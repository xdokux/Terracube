#include "/lib/all_the_libs.glsl"
void main() {
	#ifdef ROUND_SUN
	discard;
	return;
	#endif
	gl_FragData[0] = vec4(0, 0, 0, 1);
}
