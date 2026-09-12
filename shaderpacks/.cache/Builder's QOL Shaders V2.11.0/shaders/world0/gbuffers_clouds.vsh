#version 120

uniform mat4 gbufferModelViewInverse;

varying vec2 texcoord;
varying vec3 normal;
varying vec3 vPosPlayer;
varying vec3 vPosView;
varying vec4 tint;

void main() {
	vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vPosPlayer = mat3(gbufferModelViewInverse) * vPosView;
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	tint = gl_Color;
	normal = gl_Normal * 0.5 + 0.5;
}