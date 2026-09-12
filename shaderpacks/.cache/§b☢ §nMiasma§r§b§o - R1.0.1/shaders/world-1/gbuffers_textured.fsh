#version 130

#include "/settings.glsl"

uniform sampler2D lightmap;
uniform sampler2D texture;

uniform float far, near;
uniform vec3 fogColor;
uniform int isEyeInWater;

in vec2 lmcoord;
in vec2 texcoord;
in vec3 viewPos;
in vec4 glcolor;

in vec3 viewSpaceGeoNormal;

void main() {
	vec4 color = texture2D(texture, texcoord) * glcolor;
	color *= texture2D(lightmap, lmcoord);
	
	color.rgb = mix(color.rgb, vec3(1, 0.58, 0.73), 0.1);

	#if FOG == 1
	#if DISTANT_HORIZONS == true
	float farW = far;
	float distW = 7;
	
	if(isEyeInWater == 1) {
		farW = 32;
		distW = 2;
	}
	
	float dist = clamp((length(viewPos) - near) / (farW - near), 0.0f, 1.0f);
	float fogFactor = exp(-distW * (1.0 - dist));
	color.rgb = mix(color.rgb, fogColor, fogFactor);
	#else
	if(isEyeInWater == 1) {
		float dist = clamp((length(viewPos) - near) / (32 - near), 0.0f, 1.0f);
		float fogFactor = exp(-2 * (1.0 - dist));
		color.rgb = mix(color.rgb, fogColor, fogFactor);
	}
	#endif
	#endif
	
	if (isEyeInWater == 2) {
		color.rgb = vec3(0.6, 0.1, 0.0);
	}
	
	#if DISTANT_HORIZONS == true
	/* DRAWBUFFERS:02 */
	gl_FragData[0] = color;
	gl_FragData[1].rgb = (viewSpaceGeoNormal * 0.5 + 0.5);
	#else
	/* DRAWBUFFERS:0 */
	gl_FragData[0] = color;
	#endif
}
