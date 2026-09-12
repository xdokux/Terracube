#version 120
/*
Sildur's Basic Shaders:
https://www.patreon.com/Sildur
https://sildurs-shaders.github.io/
https://twitter.com/SildurFX

Permissions:
You are not allowed to edit, copy code or share my shaderpack under a different name or claim it as yours.
*/

#define final
#include "shaders.settings"

varying vec2 texcoord;
varying vec4 color;

uniform sampler2D colortex3;	//taa mixed with everything

//Disable uneeded samplers and such if neither dof nor motionblur is used.
#ifdef Depth_of_Field
#define Blur
#endif
#ifdef Motionblur
#define Blur
#endif

#ifdef Blur
uniform sampler2D depthtex0;	//everything
uniform sampler2D depthtex1;	//everything but transparency
uniform sampler2D depthtex2;	//everything but transparency+hand

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
#endif

#ifdef Depth_of_Field
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float aspectRatio;

//Dof constant values
const float focal = 0.024;
float aperture = 0.008;	
const float sizemult = DoF_Strength;
uniform float centerDepthSmooth; 
const float centerDepthHalflife = 2.0f; 

float ld(float depth) {
    return (2.0 * near) / (far + near - depth * (far - near));
}

float fast_blur[9] = float[9](-0.5, -0.375, -0.25, -0.125, 0.0, 0.125, 0.25, 0.375, 0.5);

vec3 calcDof(vec3 color, float depth0, float depth1){
	float pw = 1.0/ viewWidth;
	float z = ld(depth0)*far;
	#ifdef smoothDof
	float focus = ld(centerDepthSmooth)*far;
	#else
	float focus = ld(texture2D(depthtex0, vec2(0.5)).r)*far;
	#endif
	float pcoc = min(abs(aperture * (focal * (z - focus)) / (z * (focus - focal)))*sizemult,pw*15.0);
#ifdef Distance_Blur
	float getdist = 1-(exp(-pow(ld(depth1)/Dof_Distance_View*far,4.0)*4.0));	
	if(depth1 < 1.0-near/far/far)pcoc = getdist*pw*20.0;
#endif
	for ( int i = 0; i < 9; i++) {
		color += texture2D(colortex3, texcoord.xy + fast_blur[i]*pcoc*vec2(1.0,aspectRatio)).rgb;
	}
return color*0.11; //*0.11 = / 9
}
#endif

#ifdef Motionblur
vec3 calcMotionBlur(vec3 color, float depth1){
	vec4 currentPosition = vec4(texcoord.xy, depth1, 1.0)*2.0-1.0;
	
	vec4 fragposition = gbufferProjectionInverse * currentPosition;
		 fragposition = gbufferModelViewInverse * fragposition;
		 fragposition /= fragposition.w;
		 fragposition.xyz += cameraPosition;
	
	vec4 previousPosition = fragposition;
		 previousPosition.xyz -= previousCameraPosition;
		 previousPosition = gbufferPreviousModelView * previousPosition;
		 previousPosition = gbufferPreviousProjection * previousPosition;
		 previousPosition /= previousPosition.w;

	vec2 velocity = (currentPosition - previousPosition).st * MB_strength;
	vec2 coord = texcoord.st + velocity;

	int mb = 1;
	for (int i = 0; i < 15; ++i, coord += velocity) {
		if (coord.s > 1.0 || coord.t > 1.0 || coord.s < 0.0 || coord.t < 0.0) break;
		color += texture2D(colortex3, coord).xyz;
		++mb;
	}
return color /= mb;
}
#endif

#ifdef Tonemap
vec3 Uncharted2Tonemap(vec3 x) {
	float A = 0.28;
	float B = 0.29;		
	float C = 0.08;	//default 0.010
	float D = 0.2;
	float E = 0.025;
	float F = 0.35;
	return ((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F))-E/F;
}
#endif

void main() {

	vec4 tex = texture2D(colortex3, texcoord.xy)*color;

#ifdef Blur
//Setup depths, do it here because amd drivers suck and texture reads outside of void main or functions are broken, thanks amd
float depth0 = texture2D(depthtex0, texcoord.xy).x;
float depth1 = texture2D(depthtex1, texcoord.xy).x;
float depth2 = texture2D(depthtex2, texcoord.xy).x;
bool hand = depth0 < depth2;
if(depth0 < depth1 || !hand){
	#ifdef Depth_of_Field
		tex.rgb = calcDof(tex.rgb, depth0, depth1);
	#endif

	#ifdef Motionblur
		tex.rgb = calcMotionBlur(tex.rgb, depth1);
	#endif
}
#endif

#ifdef Crossprocess
	tex.r = (tex.r*1.34)+(tex.b+tex.g)*(-0.1);
    tex.g = (tex.g*1.2)+(tex.r+tex.b)*(-0.1);
    tex.b = (tex.b*1.1)+(tex.r+tex.g)*(-0.1);
	tex = tex / (tex + 2.2) * 3.0;
#endif

#ifdef Tonemap
	tex.rgb = Uncharted2Tonemap(tex.rgb)*gamma;
#endif

	gl_FragData[0] = tex;
}
