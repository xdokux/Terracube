#version 130

#include "/settings.glsl"
#include "/lib/colorFilter.glsl"

in float blockId;

uniform sampler2D lightmap;
uniform sampler2D texture;

uniform float far, near;
uniform vec3 fogColor;
uniform int isEyeInWater;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;

in vec2 lmcoord;
in vec2 texcoord;
in vec3 viewPos;
in vec4 glcolor;
in vec3 Normal;
in vec3 viewSpaceGeoNormal;

vec3 color3 = vec3(0.8, 0.3, 1.0);
vec3 color2 = vec3(0.2, 0.9, 1.0);
vec3 color1 = vec3(1.0, 0.9, 0.6); //самый тёмный

float pos1 = 0;
float pos2 = 0.5;
float pos3 = 1;

float getLuminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 applyGradient(float gray) {
    if (gray <= pos1) {
        return color1;
    }
    else if (gray <= pos2) {
        float t = (gray - pos1) / (pos2 - pos1);
        return mix(color1, color2, t);
    }
    else if (gray <= pos3) {
        float t = (gray - pos2) / (pos3 - pos2);
        return mix(color2, color3, t);
    }
    else {
        return color3;
    }
}

void main() {
	vec4 color = texture2D(texture, texcoord) * glcolor;
	//color *= texture2D(lightmap, lmcoord);



	if(int(blockId + 0.5) == 1) {
        color.rgb = hueShift(color.rgb, 50);
	}
	else if(int(blockId + 0.5) == 5) {
		color.rgb = hueShift(color.rgb, 100) + 0.3;
	}
	color.rgb = mix(color.rgb, vec3(1, 0.58, 0.73), 0.25);
	
	float luminance = getLuminance(color.rgb);
	vec3 gradientColor = applyGradient(luminance);
	color.rgb = mix(color.rgb, gradientColor, 0);
	
	
	
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
	//color.rgb = mix(color.rgb, vec3(0.231, 0.643, 0.639), fogFactor);
	#else
	if(isEyeInWater == 1) {
		float dist = clamp((length(viewPos) - near) / (32 - near), 0.0f, 1.0f);
		float fogFactor = exp(-2 * (1.0 - dist));
		color.rgb = mix(color.rgb, vec3(0.231, 0.643, 0.639), fogFactor);
	}
	#endif
	#endif
	
	if (isEyeInWater == 2) {
		color.rgb = vec3(0.6, 0.1, 0.0);
	}
	
	
	vec3 shadowLightDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
	float lightBrightness = clamp(dot(shadowLightDir, Normal), 0.0f, 1.0f);
	lightBrightness = pow(lightBrightness, 0.15);
	
	#if DISTANT_HORIZONS == true
	/* DRAWBUFFERS:023 */
	gl_FragData[0] = color;
	gl_FragData[1].xyz = (viewSpaceGeoNormal * 0.5 + 0.5);
	gl_FragData[2] = vec4(lightBrightness, lmcoord, 1);
	#else
	/* DRAWBUFFERS:03 */
	gl_FragData[0] = color;
	gl_FragData[1] = vec4(lightBrightness, lmcoord, 1);
	#endif
}
