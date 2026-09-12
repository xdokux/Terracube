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
varying vec3 vworldpos;
varying mat3 tbnMatrix;
varying vec2 lmcoord;
varying float iswater;
varying float mat;
varying float NdotL;

uniform vec3 shadowLightPosition;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

#ifdef Fog
varying float dist;
#endif

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

	lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	vec3 position = mat3(gbufferModelViewInverse) * (gl_ModelViewMatrix * gl_Vertex).xyz + gbufferModelViewInverse[3].xyz;
	vworldpos = position.xyz + cameraPosition;

	iswater = 0.0;
	if(dhMaterialId == DH_BLOCK_WATER) iswater = 0.95;	//don't fully remove shadows on water plane

	mat = 0.0;
	#ifdef Reflections
	#ifdef WaterReflection
		if(dhMaterialId == DH_BLOCK_WATER) mat = 1.0;
	#endif
	#ifdef TransparentReflections
		if(dhMaterialId != DH_BLOCK_WATER) mat = 2.0;
	#endif
	#endif

	gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(position, 1.0);

	#ifdef TAA
		gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
	#endif

	#ifdef Fog
		dist = length(gl_ModelViewMatrix * gl_Vertex);
	#endif

	color = gl_Color;

	//Bump & Parallax mapping
	vec3 normal = normalize(gl_NormalMatrix * gl_Normal);	
	vec3 binormal = normalize(gbufferModelView[2].xyz);
	vec3 tangent  = normalize(gbufferModelView[0].xyz);
	tbnMatrix = mat3(tangent.x, binormal.x, normal.x,
					 tangent.y, binormal.y, normal.y,
					 tangent.z, binormal.z, normal.z);

	NdotL = clamp(dot(normal, normalize(shadowLightPosition))*1.02-0.02,0.0,1.0);	
}