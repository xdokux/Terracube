#version 130

#include "/settings.glsl"

in vec2 TexCoords;

uniform int isEyeInWater;
uniform vec3 skyColor;

uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D colortex6;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D dhDepthTex0;

uniform float viewHeight, viewWidth;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;

vec3 getWorldPosDistantAware(vec2 uv, float rawDepth)
{
    if (rawDepth < 0.9999) {
        vec4 pos = gbufferProjectionInverse * (vec4(uv, rawDepth, 1.0) * 2.0 - 1.0);
        return pos.xyz / pos.w;
    } else {
        vec4 pos = gbufferProjectionInverse * (vec4(uv, 1.0, 1.0) * 2.0 - 1.0);
        vec3 farPos = pos.xyz / pos.w;

        float distantScale = 1024.0; 
        return normalize(farPos) * distantScale;
    }
}

vec3 decode (vec2 enc){
    vec2 fenc = enc*4-2;
    float f = dot(fenc,fenc);
    float g = sqrt(1-f/4.0);
    vec3 n;
    n.xy = fenc*g;
    n.z = 1-f/2;
    return n;
}

float cdist(vec2 coord) {
	return clamp(1.0 - max(abs(coord.s-0.5),abs(coord.t-0.5))*2.0, 0.0, 1.0);
}

vec3 screenSpace(vec2 coord, float depth){
	vec4 pos = gbufferProjectionInverse * (vec4(coord, depth, 1.0) * 2.0 - 1.0);
	return pos.xyz/pos.w;
}

vec3 nvec3(vec4 pos) {
    return pos.xyz/pos.w;
}

vec4 raytrace(vec4 color, vec3 normal) {
	vec3 fragpos0 = screenSpace(TexCoords.xy, texture2D(depthtex0, TexCoords.xy).x);
	vec3 rvector = reflect(fragpos0.xyz, normal.xyz);
	rvector = normalize(rvector);
	
	vec3 start = fragpos0 + rvector;
	vec3 tvector = rvector;
	
    int sr = 0;
	const int maxf = 3;
	const float ref = 0.2;
	const int rsteps = 15;
	const float inc = 2.2;
	
    for(int i = 0; i < rsteps; i++) {
        vec3 pos = nvec3(gbufferProjection * vec4(start, 1.0)) * 0.5 + 0.5;
		
        if(pos.x < 0 || pos.x > 1 || pos.y < 0 || pos.y > 1 || pos.z < 0 || pos.z > 1.0) break;
		
        vec3 fragpos1 = screenSpace(pos.xy, texture2D(depthtex1, pos.xy).x);
        float err = distance(start, fragpos1);
		if(err < pow(length(rvector), 1.35)) {
            sr++;
            if(sr >= maxf) {
                color = texture2D(colortex0, pos.xy);
				color.a = cdist(pos.xy);
				break;
            }
			tvector -= rvector;
            rvector *= ref;
		}
        rvector *= inc;
        tvector += rvector;
		start = fragpos0 + tvector;
	}
    return color;
}

float blur(sampler2D image, vec2 uv, vec2 resolution) {
  float color = 0.0f;
  vec2 off1 = vec2(1.3) * 1.5;
  color += texture2D(image, uv).x * 0.29411764705882354;
  color += texture2D(image, uv + (off1 / resolution)).x * 0.35294117647058826;
  color += texture2D(image, uv - (off1 / resolution)).x * 0.35294117647058826;
  return color; 
}

void main() {
	vec3 color = texture2D(colortex0, TexCoords).rgb;
	
	#if SSR == 1
	if(isEyeInWater != 1) {
		vec2 normal = texture2D(colortex3, TexCoords).xy;
		vec3 newnormal = decode(normal.xy);
	
		vec4 relfcolor = vec4(color, 1.0f);
		vec4 reflection = raytrace(relfcolor, newnormal.xyz);	
	
		vec3 normfrag1 = normalize(screenSpace(TexCoords, texture2D(depthtex1, TexCoords).x));

		vec3 rVector = reflect(normfrag1, normalize(newnormal.xyz));
		vec3 hV= normalize(rVector - normfrag1);

		float normalDotEye = dot(hV, normfrag1);
		float F0 = 0.09;
		float fresnel = pow(clamp(1.0 + normalDotEye, 0.0, 1.0), 4.0);
		fresnel = fresnel + F0 * (1.0 - fresnel);
	
		reflection.rgb = mix(relfcolor.rgb, reflection.rgb, reflection.a);
		color.rgb = mix(color.rgb, reflection.rgb, fresnel*1.25);
	}
	#endif
	
	#if AO == 1
	//float ao = blur(colortex6, TexCoords, vec2(viewWidth, viewHeight));
	float ao = texture2D(colortex6, TexCoords).x;
	color *= ao;
	#endif

	#if DEBUG == 0
	/*DRAWBUFFERS:0*/
	gl_FragData[0].rgb = color;
	#else
	/*DRAWBUFFERS:0*/
	gl_FragData[0].rgb = vec3(ao);
	#endif
}
