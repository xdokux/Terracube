// gbuffers_water.vsh
// Cubyz already lowers a fluid's top face by 1/8 block (see the bridge's
// cubyz_setupVertex comment on cubyz_atFluidTop) so this only adds a small
// animated ripple on top of that - it doesn't need to know it's a fluid.

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vcolor;
varying vec3 worldPosVar;

uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;

void main() {
	vec3 worldPos = (gl_ModelViewMatrix * gl_Vertex).xyz; // placeholder, refined below
	vec4 pos = gl_Vertex;

	// Ripple only the top surface (normal pointing roughly up in Cubyz's
	// Y-up-for-packs convention, i.e. gl_Normal.y > 0.5) - side/bottom faces
	// of a fluid block stay flat so they don't visibly separate from it.
	if (gl_Normal.y > 0.5) {
		vec3 approxWorld = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
		float wave = sin(approxWorld.x * 0.6 + frameTimeCounter * 1.3)
		           + sin(approxWorld.z * 0.7 - frameTimeCounter * 1.7);
		pos.y += wave * 0.035;
	}

	gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * pos;

	viewPos = (gl_ModelViewMatrix * pos).xyz;
	worldPosVar = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
	normal = normalize(gl_NormalMatrix * gl_Normal);

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	vcolor = gl_Color;
}
