#version 130

#include "/lib/whatTime.glsl"

uniform float viewHeight;
uniform float viewWidth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;

in vec2 TexCoords;
in vec4 Color;

uniform int worldTime;
uniform int isEyeInWater;
uniform sampler2D texture;

in vec4 starData; //rgb = star color, a = flag for weather or not this pixel is a star.
float timeCounter;


float fogify(float x, float w) {
	return w / (x * x + w);
}

vec3 calcSkyColor(vec3 pos) {
	float upDot = dot(pos, gbufferModelView[1].xyz);
	vec3 fogToxicColor = mix(vec3(0.73, 0.71, 1)*0.35f, vec3(0.231, 0.643, 0.639), timeCounter);
	return mix(fogToxicColor * 1.1, fogToxicColor, fogify(max(upDot, 0.0), 0.05));
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f*f*(3.0-2.0*f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void main()
{
	vec3 color;
	
	timeCounter = smoothTransition(worldTime);
	
	if (starData.a > 0.5) {
		color = starData.rgb * 0.65;
	}
	else {
		vec4 pos = vec4(gl_FragCoord.xy / vec2(viewWidth, viewHeight) * 2.0 - 1.0, 1.0, 1.0);
		pos = gbufferProjectionInverse * pos;
		color = calcSkyColor(normalize(pos.xyz));
	}
	
	if(isEyeInWater == 1) {
		color = vec3(0.322, 0.855, 0.996);
	}
	
	/* DRAWBUFFERS:03 */
    gl_FragData[0] = vec4(color.rgb, 1.0);
    gl_FragData[1] = vec4(1.0);
}
