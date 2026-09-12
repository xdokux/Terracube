#include "/lib/all_the_libs.glsl"
#include "/generic/water.glsl"
attribute vec2 mc_Entity;
attribute vec2 mc_midTexCoord;

out vec2 texcoord;
out vec4 glcolor;

flat out vec3 Normal;
flat out float Material;

out vec3 PlayerPos;

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	glcolor = gl_Color;

	Normal = normalize(gl_NormalMatrix * gl_Normal);
	Material = (mc_Entity.x - 10000.0);

	gl_Position = ftransform();
	
	gl_Position.xyz = distort(gl_Position.xyz);
}
