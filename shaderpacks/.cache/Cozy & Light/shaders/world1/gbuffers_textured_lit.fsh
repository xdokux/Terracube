#version 460 compatibility

uniform float alphaTestRef = 0.1;
uniform float worldTime;

uniform sampler2D lightmap;
uniform sampler2D gtexture;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 vertexPosition;
in float depth;
in vec3 normal;

const bool shadowcolor0Nearest = true;
const bool shadowtex0Nearest = true;
const bool shadowtex1Nearest = true;

#include "/world1/lib_world1.glsl"

/* DRAWBUFFERS: 016 */
layout(location = 0) out vec4 outColor0;
layout(location = 1) out vec4 outColor1;
layout(location = 4) out vec4 outColor4;

void main() {
	vec4 color = texture(gtexture, texcoord) * glcolor;

	color.rgb = pow(color.rgb, vec3(2.2));
	
	if (color.a < alphaTestRef) {
		discard;
	}

	vec2 lm = lmcoord;

	// Lighting

	// Adjust lightmap coords
	//lm.x = pow(lm.x, 4.0);
	// Avoids weird issues when lm.x is 0 or 1
	//lm.x = clamp(lm.x, 1.0/32.0, 31.0/32.0);

	//color *= pow(texture2D(lightmap, vec2(31.0/32.0, lm.y)), vec4(2.2));

	lm.x = pow(lm.x, 3.0);

	// Darken with lightmap
	color.rgb *= mix(lmShadowColor, vec3(1.0), clamp(lm.y + lm.x, 0.0, 1.0));

	// Diffuse lighting kinda
	color.rgb *= mix(lmShadowColor, vec3(1.0), clamp(dot(normal, vec3(0.0, 1.0, 0.0)) + lm.x, 0.4, 1.0));

	// Brighten light from light sources
	color.rgb *= mix(vec3(1.0), blockLightColor, lm.x);

	// Underwater stuff
	if(isEyeInWater == 1)
	{
		color.rgb *= waterTint;
	}

	// Fog
	vec3 densities = GetFogDensities(isEyeInWater);
	vec3 fogFactors = (exp(-densities * depth/192.0) - 1.0) * (1.0 - lm.x*0.6) + 1.0;
	vec3 fogCol = GetLightColor(isEyeInWater);
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
}