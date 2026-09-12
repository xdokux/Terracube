#include "/lib/all_the_libs.glsl"
#include "/generic/lighting/gbuffers.vsh"

out vec4 glcolor;
out vec2 texcoord;
void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	glcolor = gl_Color;
	vec3 ViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vec3 WorldPos = mat3(gbufferModelViewInverse) * ViewPos;
	WorldPos += cameraPosition;

	WorldPos.xz += sin(WorldPos.y/WAVE_SIZE * frameTimeCounter*WAVE_SPEED/100)*2.5;
	
	WorldPos -= cameraPosition;
	WorldPos = mat3(gbufferModelView) * WorldPos;
	gl_Position = gl_ProjectionMatrix * vec4(WorldPos, 1);
}

