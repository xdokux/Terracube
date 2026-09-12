#version 120
/*
Sildur's Enhanced Default:
https://www.patreon.com/Sildur
https://sildurs-shaders.github.io/
https://twitter.com/SildurFX
https://www.curseforge.com/minecraft/customization/sildurs-enhanced-default

Permissions:
You are not allowed to edit, copy code or share my shaderpack under a different name or claim it as yours.
*/

#define gbuffers_textured
#include "shaders.settings"

varying vec4 color;
varying vec2 lmcoord;
varying float NdotL;
varying float dist;
varying vec2 texcoord;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;

#ifdef TAA
uniform float viewWidth;
uniform float viewHeight;
vec2 texelSize = vec2(1.0/viewWidth,1.0/viewHeight);
uniform int framemod8;
const vec2[8] offsets = vec2[8](vec2(1./8.,-3./8.),
								vec2(-1.,3.)/8.,
								vec2(5.0,1.)/8.,
								vec2(-3,-5.)/8.,
								vec2(-5.,5.)/8.,
								vec2(-7.,-1.)/8.,
								vec2(3,7.)/8.,
								vec2(7.,-7.)/8.);
#endif

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	vec3 position = mat3(gbufferModelViewInverse) * (gl_ModelViewMatrix * gl_Vertex).xyz + gbufferModelViewInverse[3].xyz;

	gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(position, 1.0);

	#ifdef TAA
		gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
	#endif

	color = gl_Color;

	dist = length(gl_ModelViewMatrix * gl_Vertex);
	NdotL = clamp(dot(normalize(gl_NormalMatrix * gl_Normal), normalize(shadowLightPosition))*1.02-0.02,0.0,1.0);	
}