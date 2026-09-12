#include "/lib/all_the_libs.glsl"

#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/shadow/rsm.glsl"

// Denoise pass for GI

in vec2 texcoord;

/* RENDERTARGETS:3 */
layout(location = 0) out vec4 GIDenoise;

void main() {
	bool IsDH;
	float CurrentDepth = get_depth(texcoord, IsDH);
    if(CurrentDepth >= 1 || (CurrentDepth <= 0.56)) GIDenoise = vec4(0);
	else GIDenoise = gi_denoise(colortex3, texcoord, vec2(1, 0), CurrentDepth, IsDH);
}
