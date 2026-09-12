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

varying vec4 color;
varying vec3 vworldpos;
varying vec2 lmcoord;
varying mat3 tbnMatrix;
varying float iswater;
varying float mat;
varying float NdotL;

uniform int isEyeInWater;
uniform float frameTimeCounter;
uniform float viewHeight;
uniform float viewWidth;
uniform sampler2D depthtex0;
uniform sampler2D lightmap;

#ifdef Fog
varying float dist;
uniform float far;
uniform int dhRenderDistance;
#if defined(IS_IRIS) || MC_VERSION >= 11802	//optifine added fog uniforms in 1.18.2
uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;
#endif
#endif

#ifdef Reflections
uniform sampler2D noisetex;

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

vec4 encode (vec3 n){
    return vec4(n.xy*inversesqrt(n.z*8.0+8.0) + 0.5, mat/2.0, 1.0);
}

void main() {

	//Fix DH rendering, could be changed to depthtex1 to allow rendering through stained glass
    if(texture2D(depthtex0, gl_FragCoord.xy / vec2(viewWidth, viewHeight)).x < 1.0) discard;

	#ifndef customLight
		vec4 tex = texture2D(lightmap, lmcoord.xy) * color;
	#else
		//Mix default MC skylight with custom emissive light
		vec4 tex = color;
		float torchmap = clamp(lmcoord.x-0.5/16.0, 0.0, 1.0); //must be clamped to fix enchanted items
		tex.rgb *= mix(texture2D(lightmap, vec2(0.5 / 16.0, lmcoord.y)).rgb, vec3(emissive_R,emissive_G,emissive_B)*torchmap, torchmap);
	#endif

	vec4 normal = vec4(0.0); //fill the buffer with 0.0 if not needed, improves performance

	//shading
	tex.rgb *= clamp((1.0 + NdotL) * 0.65,  0.0, 1.0);

	#ifdef Colorboost
		tex.rgb = pow(tex.rgb*1.20, vec3(1.20));
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
	//improve normal water and DH blend
	tex.rgb *= 0.6;
	}
	//improve normal ice and DH blend
	tex.rgb *= 0.86;

	#ifdef Fog
    	float newFar = max(far, float(dhRenderDistance * 16.0));
    	#if defined(IS_IRIS) || MC_VERSION >= 11802	//optifine added fog uniforms in 1.18.2
    		tex.rgb = mix(tex.rgb, fogColor, clamp(max((dist - fogStart) / max(fogEnd - fogStart, 0.0001), dist / newFar * 12.5 - 11.5), 0.0, 1.0));
		#else
    		tex.rgb = mix(tex.rgb, gl_Fog.color.rgb, (isEyeInWater > 0.9) ? clamp(1.0 - exp(-dist * gl_Fog.density), 0.0, 1.0) : clamp(max((dist - gl_Fog.start) / max(gl_Fog.end - gl_Fog.start, 0.0001), dist / newFar * 12.5 - 11.5), 0.0, 1.0));
		#endif
	#endif

	gl_FragData[0] = tex;
	gl_FragData[1] = encode(normal.xyz);
}