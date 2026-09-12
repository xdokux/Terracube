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

#define composite1
#define gbuffers_clouds
#include "shaders.settings"

varying vec2 texcoord;
varying vec4 color;
#ifdef Fog
varying float dist;
#endif

#ifdef TAA
uniform float viewHeight;
uniform float viewWidth;
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
	gl_Position = ftransform();
#ifdef Fog
	dist = length(gl_ModelViewMatrix * gl_Vertex);
#endif	
#ifdef TAA
	gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
#endif

	texcoord = (gl_MultiTexCoord0).xy;
	
	color = gl_Color;
}
