#version 120
/* DRAWBUFFERS:02 */
/*
Sildur's Basic Shaders:
https://www.patreon.com/Sildur
https://sildurs-shaders.github.io/
https://twitter.com/SildurFX

Permissions:
You are not allowed to edit, copy code or share my shaderpack under a different name or claim it as yours.
*/

#define gbuffers_textured
#include "shaders.settings"

/* Don't remove me
const int gcolorFormat = RGBA8;
const int gnormalFormat = RGBA8;
const int compositeFormat = RGBA8;
-----------------------------------------*/

varying vec4 color;
varying mat3 tbnMatrix;
varying vec2 texcoord;
varying vec2 lmcoord;
varying float mat;
uniform sampler2D normals;
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform vec4 entityColor;
uniform int isEyeInWater;
uniform int entityId;
uniform vec3 shadowLightPosition;
varying float NdotL;

varying float dist;

#ifdef Fog
uniform float far;
#if defined(IS_IRIS) || MC_VERSION >= 11802	//optifine added fog uniforms in 1.18.2
uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;
#endif
#ifdef DISTANT_HORIZONS
uniform int dhRenderDistance;
#endif
#ifdef VOXY
uniform int vxRenderDistance;
#endif
#endif

#if nMap == 2
#extension GL_ARB_shader_texture_lod : enable
varying vec3 viewVector;
varying vec4 vtexcoordam; // .st for add, .pq for mul
varying vec2 vtexcoord;
varying float isblock; //mc_Entity.x, hack to only apply pom to blocks
bool block = isblock > 0.0 || isblock < 0.0; //get defined and undefined blocks

uniform ivec2 atlasSize; 
vec2 atlasAspect = vec2(atlasSize.y/float(atlasSize.x), atlasSize.x/float(atlasSize.y));

mat2 dFdxy = mat2(dFdx(vtexcoord.xy*vtexcoordam.pq), dFdy(vtexcoord.xy*vtexcoordam.pq));	
vec4 readNormal(in vec2 coord){
	return texture2DGradARB(normals,fract(coord)*vtexcoordam.pq+vtexcoordam.st,dFdxy[0],dFdxy[1]);
}

vec4 calcPOM(vec4 albedo){
	if(block){	//only apply to blocks else return albedo
	vec2 newCoord = vtexcoord.xy*vtexcoordam.pq+vtexcoordam.st;

	if (dist < POM_DIST && viewVector.z < 0.0 && readNormal(vtexcoord.xy).a < 1.0){
		const float res_stepths = 0.33 * POM_RES;
		vec2 viewCorrection = max(vec2(vtexcoordam.q/vtexcoordam.p*atlasAspect.x,1.0), vec2(1.0,vtexcoordam.p/vtexcoordam.q*atlasAspect.y));
		vec2 pstepth = viewCorrection * viewVector.xy * POM_DEPTH / (-viewVector.z * POM_RES);
		vec2 coord = vtexcoord.xy;
		for (int i= 0; i < res_stepths && (readNormal(coord.xy).a < 1.0-float(i)/POM_RES); ++i) coord += pstepth;
	
		newCoord = fract(coord.xy)*vtexcoordam.pq+vtexcoordam.st;
	}
	albedo = texture2DGradARB(texture, newCoord, dFdxy[0],dFdxy[1])* texture2D(lightmap, lmcoord.st)*color;

	vec3 bmap = normalize((texture2DGradARB(normals, newCoord, dFdxy[0],dFdxy[1]).rgb*2.0-1.0) * tbnMatrix);
	float bmaplight = max(dot(bmap, normalize(shadowLightPosition)),0.0);
		albedo.rgb *= clamp(1.0 + bmaplight - 1.0*NdotL, 1.0, 1.5);

	#ifdef draw_bmap
		if(block)albedo.rgb = bmap;
	#endif
	return albedo;
	} else return albedo;
}
#endif

void main() {

#ifndef customLight
	vec4 tex = texture2D(texture, texcoord.st) * texture2D(lightmap, lmcoord.xy) * color;
#else
	//Mix default MC skylight with custom emissive light
	vec4 tex = texture2D(texture, texcoord.st) * color;
	float torchmap = clamp(lmcoord.x-0.5/16.0, 0.0, 1.0); //must be clamped to fix enchanted items
	tex.rgb *= mix(texture2D(lightmap, vec2(0.5 / 16.0, lmcoord.y)).rgb, vec3(emissive_R,emissive_G,emissive_B)*torchmap, torchmap);
#endif

	//Restore shading, like default minecraft.
	tex.rgb *= clamp((1.0 + NdotL) * 0.65,  0.0, 1.0);

#if nMap == 1
	vec3 bmap = normalize((texture2D(normals, texcoord.xy).xyz*2.0-1.0) * tbnMatrix);
	float bmaplight = max(dot(bmap, normalize(shadowLightPosition)),0.0);
		tex.rgb *= clamp(1.0 + bmaplight - 1.0*NdotL, 1.0, 1.5);
	#ifdef draw_bmap
		tex.rgb = bmap;
	#endif
#elif nMap == 2
	tex = calcPOM(tex);
#endif

#ifdef Colorboost
	tex.rgb = pow(tex.rgb*1.20, vec3(1.20));
#endif

#ifdef MobsFlashRed
	tex.rgb = mix(tex.rgb,entityColor.rgb,entityColor.a);
#endif	

	//Fix lightning bolts
	if(entityId == 11000.0) tex = texture2D(lightmap, lmcoord.xy)*color;

#ifdef Fog
    float newFar = far;
	#ifdef DISTANT_HORIZONS
    	newFar = max(far, float(dhRenderDistance * 16.0));
	#endif 
	#ifdef VOXY
    	newFar = max(far, float(vxRenderDistance * 16.0));
	#endif
    #if defined(IS_IRIS) || MC_VERSION >= 11802	//optifine added fog uniforms in 1.18.2
    	tex.rgb = mix(tex.rgb, fogColor, clamp(max((dist - fogStart) / max(fogEnd - fogStart, 0.0001), dist / newFar * 12.5 - 11.5), 0.0, 1.0));
	#else
    	tex.rgb = mix(tex.rgb, gl_Fog.color.rgb, (isEyeInWater > 0.9) ? clamp(1.0 - exp(-dist * gl_Fog.density), 0.0, 1.0) : clamp(max((dist - gl_Fog.start) / max(gl_Fog.end - gl_Fog.start, 0.0001), dist / newFar * 12.5 - 11.5), 0.0, 1.0));
	#endif
#endif

	gl_FragData[0] = tex;
	gl_FragData[1] = vec4(0.0, 0.0, mat/2.0, 1.0); //Todo encode mats into colors to save a buffer.
}