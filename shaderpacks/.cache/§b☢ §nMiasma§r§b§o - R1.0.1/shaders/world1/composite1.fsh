#version 130

const bool colortex1Clear = false;
/*
const int colortex0Format = RGB8;
const int colortex1Format = RGBA8;
*/

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

const vec3 MOD3 = vec3(.1031,.11369,.13787);
float hash12(vec2 p)
{
	vec3 p3  = fract(vec3(p.xyx) * MOD3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 getPosition(vec2 uv) {
    float z = texture2D(dhDepthTex1, uv).r;
	vec2 ndc = uv * 2.0 - 1.0;
	vec4 clip = vec4(ndc, z * 2.0 - 1.0, 1.0);
	vec4 view = dhProjectionInverse * clip;
	view /= view.w;
	return view.xyz;
}

vec3 getNormal(vec2 uv) {
    vec3 n = texture2D(colortex2, texcoord).xyz * 2.0 - 1.0;
    return normalize(n);
}

float doAO(vec2 uv, vec2 dir, vec3 p, vec3 n) {
    vec3 samplePos = getPosition(uv + dir) - p;
    float dist = length(samplePos);
    vec3  v    = samplePos / dist;
    float d    = dist * 2.0f;
    float ao = max(dot(n, v), 0.0) / (1.0 + d);
    ao *= smoothstep(10f, 10f * 0.5, dist);
    return ao;
}

float spiralAO(vec2 uv, vec3 p, vec3 n, float rad) {
    const float golden = 2.4; // ≈ π*(3 - √5)
    float ao = 0.0;
    float inv = 1.0 / float(16);
	float radius = 0.0;
    float phase = hash12((uv + frameTimeCounter) * 100.0) * 6.28;
    float step = rad * inv;
    for (int i = 0; i < 16; i++) {
        vec2 dir = vec2(sin(phase), cos(phase));
		radius += step;
        phase += golden;
        ao += doAO(uv, dir * radius, p, n);
    }
    return ao * inv;
}

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
			vec3 p = getPosition(texcoord);
			vec3 n = getNormal(texcoord);
			float rad = 1.0f / abs(p.z);
			
			float rawAO = spiralAO(texcoord, p, n, rad);
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
