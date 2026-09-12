// gbuffers_terrain.vsh

varying vec2 texcoord;
varying vec2 lmcoord;   // .x = torchlight 0..1, .y = sky access 0..1 (see bridge's cubyz_setupVertex)
varying vec3 normal;    // view-space normal
varying vec3 viewPos;   // view-space position, used to reconstruct world pos in the fragment stage
varying vec4 vcolor;

void main() {
	gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;

	viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
	normal = normalize(gl_NormalMatrix * gl_Normal);

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;

	vcolor = gl_Color;
}
