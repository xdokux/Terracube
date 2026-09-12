#version 120
/* DRAWBUFFERS:0 */
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

varying vec4 color;
varying vec2 lmcoord;
uniform sampler2D lightmap;
uniform int isEyeInWater;
varying float NdotL;
varying float dist;
uniform float frameTimeCounter;
uniform float far;

#ifdef Fog
uniform int dhRenderDistance;
#if defined(IS_IRIS) || MC_VERSION >= 11802	//optifine added fog uniforms in 1.18.2
uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;
#endif
#endif

uniform sampler2D depthtex0;
uniform float viewWidth;
uniform float viewHeight;

void main() {

	//Fix DH rendering
	float dither = fract(0.75487765 * gl_FragCoord.x + 0.56984026 * gl_FragCoord.y);
		  dither = fract(frameTimeCounter * 16.0 + dither);
	if(dist < dither * 24.0 - 16.0 + far) discard;
	else if(texture2D(depthtex0, gl_FragCoord.xy / vec2(viewWidth, viewHeight)).x != 1.0) discard;

#ifndef customLight
	vec4 tex = texture2D(lightmap, lmcoord.xy) * color;
#else
	//Mix default MC skylight with custom emissive light
	vec4 tex = color;
	float torchmap = clamp(lmcoord.x-0.5/16.0, 0.0, 1.0); //must be clamped to fix enchanted items
	tex.rgb *= mix(texture2D(lightmap, vec2(0.5 / 16.0, lmcoord.y)).rgb, vec3(emissive_R,emissive_G,emissive_B)*torchmap, torchmap);
#endif

	//Restore shading, like default minecraft.
	tex.rgb *= clamp((1.0 + NdotL) * 0.65,  0.0, 1.0);

#ifdef Colorboost
	tex.rgb = pow(tex.rgb*1.20, vec3(1.20));
#endif

	#ifdef Fog
    	float newFar = max(far, float(dhRenderDistance * 16.0));
    	#if defined(IS_IRIS) || MC_VERSION >= 11802	//optifine added fog uniforms in 1.18.2
    		tex.rgb = mix(tex.rgb, fogColor, clamp(max((dist - fogStart) / max(fogEnd - fogStart, 0.0001), dist / newFar * 12.5 - 11.5), 0.0, 1.0));
		#else
    		tex.rgb = mix(tex.rgb, gl_Fog.color.rgb, (isEyeInWater > 0.9) ? clamp(1.0 - exp(-dist * gl_Fog.density), 0.0, 1.0) : clamp(max((dist - gl_Fog.start) / max(gl_Fog.end - gl_Fog.start, 0.0001), dist / newFar * 12.5 - 11.5), 0.0, 1.0));
		#endif
	#endif

	gl_FragData[0] = tex;
}