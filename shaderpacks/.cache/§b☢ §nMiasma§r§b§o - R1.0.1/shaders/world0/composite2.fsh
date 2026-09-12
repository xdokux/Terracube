#version 130

#include "/lib/ao.glsl"

const bool colortex1Clear = false;

in vec2 texcoord;

uniform float dhFarPlane;
uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D dhDepthTex0;
uniform sampler2D dhDepthTex1;
uniform sampler2D noisetex;

uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform mat4 dhProjectionInverse;

void main()
{
    vec3 color = texture(colortex0, texcoord).rgb;
	vec3 norm = texture(colortex2, texcoord).rgb;
	
	float Depthv1 = texture2D(dhDepthTex0, texcoord).r;
	float Depthv0 = texture2D(depthtex0, texcoord).r;
	
	if(Depthv0 == 1.0f)
	{		
		vec2 ndc = texcoord * 2.0 - 1.0;
		vec4 clip = vec4(ndc, Depthv1 * 2.0 - 1.0, 1.0);
		vec4 view = dhProjectionInverse * clip;
		view /= view.w;
		
		float distanceFade = clamp(length(view.xyz) / (dhFarPlane / 1.5), 0.0, 1.0);
		float fade = pow(smoothstep(0.0, 1.0, 1.0 - distanceFade), 0.25);
		
		float aoStrength = 1.0f;
		
		if (fade > 0.90f) {
			vec3 p = getPosition(texcoord, dhProjectionInverse, dhDepthTex1);
			vec3 n = getNormal(texcoord, colortex2);
			float rad = 1.0f / abs(p.z);
			
			float rawAO = spiralAO(texcoord, p, n, rad, dhProjectionInverse, frameTimeCounter, dhDepthTex1);
			aoStrength = 1.0 - rawAO * 5f;
		}
		
		if(length(norm) != 0.0f)
		{
			color *= aoStrength;
		}
		
		/*DRAWBUFFERS:0*/
		gl_FragData[0].rgb = vec3(color);
	}
	else
	{
		/*DRAWBUFFERS:0*/
		gl_FragData[0].rgb = vec3(color);
	}
}
