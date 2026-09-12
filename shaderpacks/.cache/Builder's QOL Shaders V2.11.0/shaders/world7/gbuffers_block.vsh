#version 120

uniform mat4 gbufferModelViewInverse;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec3 vPosPlayer;
varying vec3 vPosView;
varying vec4 tint;

void main() {
	vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vPosPlayer = mat3(gbufferModelViewInverse) * vPosView;
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	gl_Position = ftransform();
	tint = gl_Color;

	vec3 realNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
	float glmult = dot(vec4(abs(realNormal.x), abs(realNormal.z), max(realNormal.y, 0.0), max(-realNormal.y, 0.0)), vec4(0.6, 0.8, 1.0, 0.5));
	glmult = mix(glmult, 1.0, lmcoord.x * lmcoord.x); //increase brightness when block light is high
	tint.rgb *= glmult;
}