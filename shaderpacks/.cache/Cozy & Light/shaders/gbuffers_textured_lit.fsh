#version 460 compatibility

uniform float alphaTestRef = 0.1;
uniform float worldTime;

uniform sampler2D lightmap;
uniform sampler2D gtexture;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 vertexPosition;
in vec4 shadowPos;
in float depth;
in vec3 normal;

const bool shadowcolor0Nearest = true;
const bool shadowtex0Nearest = true;
const bool shadowtex1Nearest = true;

#include "distort.glsl"
#include "/lib.glsl"
#include "shadow.glsl"

/* DRAWBUFFERS: 01436 */
layout(location = 0) out vec4 outColor0;
layout(location = 1) out vec4 outColor1;
layout(location = 2) out vec4 outColor2;
layout(location = 3) out vec4 outColor3;
layout(location = 4) out vec4 outColor4;

void main() {
	vec4 color = texture(gtexture, texcoord) * glcolor;

	color.rgb = pow(color.rgb, vec3(2.2));
	
	if (color.a < alphaTestRef) {
		discard;
	}

	vec2 lm = lmcoord;

	float inShadow = 0.0;

	// Shadows
	if (shadowPos.w < 0.0) {
		//surface is facing away from shadowLightPosition -> definitely in shadow.
		inShadow = 1.0;
	}
	if (shadowPos.w > 0.0) {
		//surface is facing towards shadowLightPosition
		inShadow = GetShadow();

	#ifdef COLORED_SHADOWS
		//when colored shadows are enabled and there's something translucent between the sun and the nearest opaque thing.
		float shadowDepth0 = texture2D(shadowtex0, shadowPos.xy).r;
		float shadowDepth1 = texture2D(shadowtex1, shadowPos.xy).r;
		if (shadowDepth0 < shadowDepth1) {
			//surface has translucent object between it and the sun. modify its color.
			//if the block light is high, modify the color less.
			vec4 shadowLightColor = texture2D(shadowcolor0, shadowPos.xy);
			shadowLightColor.rgb = pow(shadowLightColor.rgb, vec3(2.2));
			//make colors more intense when the shadow light color is more opaque.
			shadowLightColor.rgb = mix(vec3(1.0), shadowLightColor.rgb, clamp(shadowLightColor.a * 2.0, 0.0, 1.0));
			//also make colors less intense when the block light level is high.
			shadowLightColor.rgb = mix(shadowLightColor.rgb, vec3(1.0), lm.x);
			//apply the color.
			float shadowFactor = 1.0 - ShadowBrightnessAdjusted(lm.x);
			vec3 shadowTint = mix(vec3(1.0), shadowLightColor.rgb, shadowFactor);
			shadowTint = mix(shadowTint, vec3(1.0), inShadow);
			color.rgb *= shadowTint;
		}
	#endif
	}


	// Adjust normals for raining
	if(dot(normal, vec3(0.0, 1.0, 0.0)) > 0.95) {
		//color = vec4(1.0);
	}


	// Lighting

	// Adjust lightmap coords
	//lm.x = pow(lm.x, 4.0);
	// Avoids weird issues when lm.x is 0 or 1
	//lm.x = clamp(lm.x, 1.0/32.0, 31.0/32.0);

	//color *= pow(texture2D(lightmap, vec2(31.0/32.0, lm.y)), vec4(2.2));

	lm.x = pow(lm.x, 3.0);

	// Darken shadowed regions
	float shadowFactor = mix(inShadow, 0.0, ShadowBrightnessAdjusted(lm.x));
	color.rgb *= mix(vec3(1.0), shadowColor, shadowFactor);

	// Darken with lightmap
	color.rgb *= mix(lmShadowColor, vec3(1.0), clamp(lm.y + lm.x, 0.0, 1.0));

	// Diffuse lighting
	float sunDot = clamp(shadowPos.w, 0.0, 1.0);
	color.rgb *= mix(shadowColor, vec3(1.0), clamp(inShadow + ShadowBrightnessAdjusted(lm.x) + sunDot, 0.0, 1.0));

	// Overall darkening for night/cave/rain
	color.rgb *= mix(nightColor, vec3(1.0), clamp(lm.x + GetSunVisibility()*(1.0 - inCave), 0.0, 1.0)); // darken for night and cave
	color.rgb = mix(color.rgb, vec3(dot(vec3(0.2126, 0.7152, 0.0722), color.rgb)), rainStrength * 0.5 * (1.0 - inCave) * (1.0 - lm.x)); // desature for rain
	color.rgb *= mix(vec3(1.0), nightColor, rainStrength * 1.0 * GetSunVisibility() * (1.0 - lm.x) * (1.0 - inCave)); // darken for rain

	// Brighten parts in direct sunlight
	color.rgb *= mix(GetShadowLightColor(GetSunVisibility(), rainStrength), vec3(1.0), clamp(inShadow + 1.0 - sunDot, 0.0, 1.0));

	// Brighten light from light sources
	vec3 blockLight = mix(blockLightColor, vec3(1.0), clamp(GetSunVisibility() * 0.9 - rainStrength * 1.0 - inCave, 0.0, 1.0));
	color.rgb *= mix(vec3(1.0), blockLight, lm.x);

	// Underwater stuff
	if(isEyeInWater == 1)
	{
		color.rgb *= waterTint;
	}

	// Fog
	vec3 densities = GetFogDensities(GetSunVisibility(), rainStrength, isEyeInWater);
	vec3 fogFactors = (exp(-densities * depth/192.0) - 1.0) * (1.0 - lm.x*0.6) + 1.0;
	vec3 fogCol = GetLightColor(GetSunVisibility(), rainStrength, isEyeInWater);
	color.rgb = mix(color.rgb, fogCol, pow(1.0 - fogFactors, vec3(2.0)));
	vec3 fogMask = mix(vec3(0.0), vec3(1.0), pow(1.0 - fogFactors.g, 2.0));

	outColor4 = vec4(0.0, 0.0, 0.0, 1.0);

	if(isEyeInWater == 2) {
		color.rgb = mix(color.rgb, lavaFogColor, clamp(depth*lavaFogDen, 0.0, 1.0));
		outColor4 = mix(outColor4, vec4(1.0), clamp(depth*lavaFogDen, 0.0, 1.0));
	}
	if(isEyeInWater == 3) {
		color.rgb = mix(color.rgb, snowFogColor, clamp(depth*snowFogDen, 0.0, 1.0));
		outColor4 = mix(outColor4, vec4(1.0), clamp(depth*lavaFogDen, 0.0, 1.0));
	}

	color.rgb = pow(color.rgb, vec3(1.0/2.2));

	outColor0 = color;
	//outColor0 = vec4(fogMask, 1.0);
	//outColor0 = vec4(shadowPos.xyz, 1.0);
	//outColor0 = texture2D(lightmap, vec2(31.0/32.0, lm.y));
	outColor1 = vec4(normal * 0.5 + 0.5, 1.0);
	outColor2 = vec4(0.0, 0.0, 0.0, 1.0);
}