#version 120
/* DRAWBUFFERS:02 */ //0=gcolor, 2=gnormal for normals
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

//Setup constants
const int	noiseTextureResolution = 128;
//----------------------------------------------------------------

/* Don't remove me
const int gcolorFormat = RGBA8;
const int gnormalFormat = RGB10_A2;
const int compositeFormat = RGBA8;
-----------------------------------------*/

varying vec4 color;
varying vec3 vworldpos;
varying mat3 tbnMatrix;
varying vec2 texcoord;
varying vec2 lmcoord;
varying float iswater;
varying float mat;
uniform sampler2D normals;
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform float rainStrength;
uniform vec4 entityColor;
uniform int isEyeInWater;
uniform int entityId;
uniform ivec2 eyeBrightnessSmooth;
uniform vec3 shadowLightPosition;

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

#ifdef Reflections
uniform sampler2D noisetex;
uniform float frameTimeCounter;

mat2 rmatrix(float rad){
	return mat2(vec2(cos(rad), -sin(rad)), vec2(sin(rad), cos(rad)));
}

float calcWaves(vec2 coord){
	vec2 movement = abs(vec2(0.0, -frameTimeCounter * 0.31365*iswater));
		 
	coord *= 0.262144;
	vec2 coord0 = coord * rmatrix(1.0) - movement * 4.0;
		 coord0.y *= 3.0;
	vec2 coord1 = coord * rmatrix(0.5) - movement * 1.5;
		 coord1.y *= 3.0;		 
	vec2 coord2 = coord + movement * 0.5;
		 coord2.y *= 3.0;
	
	float wave = 1.0 - texture2D(noisetex,coord0 * 0.005).x * 10.0;		//big waves
		  wave += texture2D(noisetex,coord1 * 0.010416).x * 7.0;		//small waves
		  wave += sqrt(texture2D(noisetex,coord2 * 0.045).x * 6.5) * 1.33;//noise texture
		  wave *= 0.0157;
	
	return wave;
}

vec3 calcBump(vec2 coord){
	const vec2 deltaPos = vec2(0.25, 0.0);

	float h0 = calcWaves(coord);
	float h1 = calcWaves(coord + deltaPos.xy);
	float h2 = calcWaves(coord - deltaPos.xy);
	float h3 = calcWaves(coord + deltaPos.yx);
	float h4 = calcWaves(coord - deltaPos.yx);

	float xDelta = ((h1-h0)+(h0-h2));
	float yDelta = ((h3-h0)+(h0-h4));

	return vec3(vec2(xDelta,yDelta)*0.45, 0.55); //z = 1.0-0.5
}
#endif

varying float NdotLight;
#ifdef Shadows
varying float NdotL;
varying vec3 getShadowpos;
uniform sampler2DShadow shadowtex0;	//normal shadows
uniform sampler2DShadow shadowtex1; //colored shadows
uniform sampler2D shadowcolor0;

//Hacky lightmap setup for emissive blocks, todo
float modlmap = 13.0-lmcoord.s*12.35; 
float torch_lightmap = max(1.5/(modlmap*modlmap)-0.00945,0.0);
vec3 emissiveLight = clamp(vec3(1.25)*torch_lightmap, 0.0, 1.0); //emissive lightmap

float shadowfilter(sampler2DShadow shadowtexture){
	vec2 offset = vec2(0.25, -0.25) / shadowMapResolution;	
	return clamp(dot(vec4(shadow2D(shadowtexture,vec3(getShadowpos.xy + offset.xx, getShadowpos.z)).x,
						  shadow2D(shadowtexture,vec3(getShadowpos.xy + offset.yx, getShadowpos.z)).x,
						  shadow2D(shadowtexture,vec3(getShadowpos.xy + offset.xy, getShadowpos.z)).x,
						  shadow2D(shadowtexture,vec3(getShadowpos.xy + offset.yy, getShadowpos.z)).x),vec4(0.25))*NdotL,0.0,1.0);
}

vec3 calcShadows(vec3 c){
	vec3 finalShading = vec3(0.0);

if(NdotL > 0.0 && rainStrength < 0.9){ //optimization, disable shadows during rain for performance boost
		float shading = shadowfilter(shadowtex0);
	#ifdef Colored_Shadows
		float cshading = shadowfilter(shadowtex1);
		finalShading = texture2D(shadowcolor0, getShadowpos.xy).rgb*(cshading-shading) + shading;
	#else
		finalShading = vec3(shading);
	#endif
	
	//avoid light leaking underground
	finalShading *= mix(max(lmcoord.t-2.0/16.0,0.0)*1.14285714286,1.0,clamp((eyeBrightnessSmooth.y/255.0-2.0/16.)*4.0,0.0,1.0));
	
	finalShading *= (1.0 - rainStrength);		//smoother transition while disabling shadows during rain
	finalShading *= (1.0 - iswater);			//disable shadows on water plane(not fully, 1.0-0.95)
}
	
return c * (1.0+finalShading+emissiveLight) * slight;
}
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

	//vec4 specularity = texture2DGradARB(specular, newCoord, dcdx, dcdy);
	vec3 bmap = normalize((texture2DGradARB(normals, newCoord, dFdxy[0],dFdxy[1]).rgb*2.0-1.0) * tbnMatrix);
	float bmaplight = max(dot(bmap, normalize(shadowLightPosition)),0.0);
	#ifdef Shadows
		albedo.rgb *= clamp((1.0 + bmaplight - 1.0 * NdotLight) * 0.75, 1.0, 1.5);
	#else
		albedo.rgb *= clamp(1.0 + bmaplight - 1.0 * NdotLight, 1.0, 1.5);
	#endif
	#ifdef draw_bmap
		if(block)albedo.rgb = bmap;
	#endif
	return albedo;
	} else return albedo;
}
#endif

vec4 encode (vec3 n){
    return vec4(n.xy*inversesqrt(n.z*8.0+8.0) + 0.5, mat/2.0, 1.0);
}

void main() {

#ifndef customLight
	vec4 tex = texture2D(texture, texcoord.st) * texture2D(lightmap, lmcoord.xy) * color;
#else
	//Mix default MC skylight with custom emissive light
	vec4 tex = texture2D(texture, texcoord.st) * color;
	float torchmap = clamp(lmcoord.x-0.5/16.0, 0.0, 1.0); //must be clamped to fix enchanted items
	tex.rgb *= mix(texture2D(lightmap, vec2(0.5 / 16.0, lmcoord.y)).rgb, vec3(emissive_R,emissive_G,emissive_B)*torchmap, torchmap);
#endif

	vec4 normal = vec4(0.0); //fill the buffer with 0.0 if not needed, improves performance

#if nMap == 1
	vec3 bmap = normalize((texture2D(normals, texcoord.xy).xyz*2.0-1.0) * tbnMatrix);
	float bmaplight = max(dot(bmap, normalize(shadowLightPosition)),0.0);
	#ifdef Shadows
		tex.rgb *= clamp((1.0 + bmaplight - 1.0 * NdotLight) * 0.75, 1.0, 1.5);
	#else
		tex.rgb *= clamp(1.0 + bmaplight - 1.0 * NdotLight, 1.0, 1.5);
	#endif
	#ifdef draw_bmap
		tex.rgb = bmap;
	#endif	
#elif nMap == 2
	tex = calcPOM(tex);
#endif

#ifdef Shadows
	tex.rgb = calcShadows(tex.rgb);
#else
	tex.rgb *= (1.0 + NdotLight) * 0.6;	//improve visuals without shadows enabled
#endif	

#ifdef Colorboost
	tex.rgb = pow(tex.rgb*1.20, vec3(1.20));
#endif

#ifdef MobsFlashRed
	tex.rgb = mix(tex.rgb,entityColor.rgb,entityColor.a);
#endif	

#ifdef Reflections	
	vec2 waterpos = (vworldpos.xz - vworldpos.y);
	if(mat > 0.9)normal = vec4(normalize(calcBump(waterpos) * tbnMatrix), 1.0); //mat > 0.9 so that only reflective blocks alter normals, boosts performance by about 30%. mat=reflective
#endif

if(iswater > 0.1){
	if(isEyeInWater > 0.9)tex.a = 0.9;	//improve alpha underwater, default is 1 (opaque)
#ifdef waterTex	
	tex.rgb *= 1.25;					//improve colors on water
#else
	#if MC_VERSION < 11300 		//Add a watercolor fallback for 1.12.2 and below, for some reason color.rgb turns out grey in older versions.
		tex = mix(tex, vec4(0.0, 0.275, 0.525, 0.75), 1.0) * texture2D(lightmap, lmcoord.st);
	#else
		tex.rgb = mix(tex.rgb, color.rgb*0.5, 1.0) * texture2D(lightmap, lmcoord.st).rgb;
	#endif	
#endif
}

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
	gl_FragData[1] = encode(normal.xyz);
}