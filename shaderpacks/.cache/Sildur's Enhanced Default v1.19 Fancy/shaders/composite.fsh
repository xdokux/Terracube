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

#define composite0
#define gbuffers_clouds //fog
#include "shaders.settings"

varying vec2 texcoord;
varying vec4 color;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D texture;
uniform sampler2D gnormal; //used by reflections and celshading
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;
uniform int isEyeInWater;

#ifdef DISTANT_HORIZONS
uniform float dhNearPlane;
uniform float dhFarPlane;
uniform sampler2D dhDepthTex0;
uniform sampler2D dhDepthTex1;
uniform mat4 dhProjection;
uniform mat4 dhProjectionInverse;
float DHdepth0 = texture2D(dhDepthTex0, texcoord.xy).x;
float DHdepth1 = texture2D(dhDepthTex1, texcoord.xy).x;
bool DH_reflective = DHdepth1 > DHdepth0;
#endif

#ifdef Fog
#if defined(IS_IRIS) || MC_VERSION >= 11802	//optifine added fog uniforms in 1.18.2
uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;
#endif
#ifdef DISTANT_HORIZONS
uniform int dhRenderDistance;
#endif
#ifdef VOXY
uniform int vxRenderDistance;
#endif
#endif

vec3 decode (vec2 enc){
    vec2 fenc = enc*4-2;
    float f = dot(fenc,fenc);
    float g = sqrt(1-f/4.0);
    vec3 n;
    n.xy = fenc*g;
    n.z = 1-f/2;
    return n;
}

vec3 nvec3(vec4 pos) {
    return pos.xyz/pos.w;
}

float cdist(vec2 coord) {
	return clamp(1.0 - max(abs(coord.s-0.5),abs(coord.t-0.5))*2.0, 0.0, 1.0);
}

vec3 toScreenSpace(vec3 pos) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
	vec3 p3 = pos * 2.0 - 1.0;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}

#ifdef SSAO
uniform float aspectRatio;
const vec2 check_offsets[25] = vec2[25](vec2(-0.4894566f,-0.3586783f),
									vec2(-0.1717194f,0.6272162f),
									vec2(-0.4709477f,-0.01774091f),
									vec2(-0.9910634f,0.03831699f),
									vec2(-0.2101292f,0.2034733f),
									vec2(-0.7889516f,-0.5671548f),
									vec2(-0.1037751f,-0.1583221f),
									vec2(-0.5728408f,0.3416965f),
									vec2(-0.1863332f,0.5697952f),
									vec2(0.3561834f,0.007138769f),
									vec2(0.2868255f,-0.5463203f),
									vec2(-0.4640967f,-0.8804076f),
									vec2(0.1969438f,0.6236954f),
									vec2(0.6999109f,0.6357007f),
									vec2(-0.3462536f,0.8966291f),
									vec2(0.172607f,0.2832828f),
									vec2(0.4149241f,0.8816f),
									vec2(0.136898f,-0.9716249f),
									vec2(-0.6272043f,0.6721309f),
									vec2(-0.8974028f,0.4271871f),
									vec2(0.5551881f,0.324069f),
									vec2(0.9487136f,0.2605085f),
									vec2(0.7140148f,-0.312601f),
									vec2(0.0440252f,0.9363738f),
									vec2(0.620311f,-0.6673451f)
									);

//modified version of Yuriy O'Donnell's SSDO (License MIT -> https://github.com/kayru/dssdo)
float calcSSDO(vec3 fragpos, vec3 normal){
	float finalAO = 0.0;
	float radius = 0.05 / (fragpos.z);
	const float attenuation_angle_threshold = 0.1;
	const int num_samples = 16;	
	const float ao_weight = 1.0;

	for( int i=0; i<num_samples; ++i ){
	    vec2 texOffset = pow(length(check_offsets[i].xy),0.5)*radius*vec2(1.0,aspectRatio)*normalize(check_offsets[i].xy);
		vec2 newTC = texcoord+texOffset;

		vec3 t0 = toScreenSpace(vec3(newTC, texture2D(depthtex0, newTC).x));

		vec3 center_to_sample = t0.xyz - fragpos.xyz;

		float dist = length(center_to_sample);

		vec3 center_to_sample_normalized = center_to_sample / dist;
		float attenuation = 1.0-clamp(dist/6.0,0.0,1.0);
		float dp = dot(normal, center_to_sample_normalized);

		attenuation = sqrt(max(dp,0.0))*attenuation*attenuation * step(attenuation_angle_threshold, dp);
		finalAO += attenuation * (ao_weight / num_samples);
	}
	return pow(1.0-finalAO, 0.5);
}
#endif

#ifdef Reflections
uniform mat4 gbufferProjection;
uniform ivec2 eyeBrightnessSmooth;

vec4 raytrace(vec4 color, vec3 normal) {
	vec3 fragpos0 = toScreenSpace(vec3(texcoord.xy, texture2D(depthtex0, texcoord.xy).x));
#ifdef DISTANT_HORIZONS
	if(DH_reflective) fragpos0 = nvec3(dhProjectionInverse * (vec4(texcoord, DHdepth0, 1.0) * 2.0 - 1.0));
#endif
	vec3 rvector = reflect(fragpos0.xyz, normal.xyz);
		 rvector = normalize(rvector);
	
	vec3 start = fragpos0 + rvector;
	vec3 tvector = rvector;
    int sr = 0;
	const int maxf = 3;				//number of refinements
	const float ref = 0.2;			//refinement multiplier
	const int rsteps = 15;
	const float inc = 2.2;			//increasement factor at each step	
    for(int i=0;i<rsteps;i++){
        vec3 pos = nvec3(gbufferProjection * vec4(start, 1.0)) * 0.5 + 0.5;
	#ifdef DISTANT_HORIZONS
		if(DH_reflective) pos = nvec3(dhProjection * vec4(start, 1.0)) * 0.5 + 0.5;
	#endif
        if(pos.x < 0 || pos.x > 1 || pos.y < 0 || pos.y > 1 || pos.z < 0 || pos.z > 1.0) break;
        vec3 fragpos1 = toScreenSpace(vec3(pos.xy, texture2D(depthtex1, pos.st).x));
	#ifdef DISTANT_HORIZONS
		if(DH_reflective) fragpos1 = nvec3(dhProjectionInverse * (vec4(pos.xy, texture2D(dhDepthTex1, pos.st).x, 1.0) * 2.0 - 1.0));
	#endif
        float err = distance(start, fragpos1);
		if(err < pow(length(rvector),1.175)){
                sr++;
                if(sr >= maxf){
                    color = texture2D(texture, pos.st);
					color.a = cdist(pos.st);
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
}/*--------------------------------------*/
#endif

#ifdef Refractions
uniform sampler2D noisetex;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelViewInverse;

mat2 rmatrix(float rad){
	return mat2(vec2(cos(rad), -sin(rad)), vec2(sin(rad), cos(rad)));
}
float calcWaves(vec2 coord){
	vec2 movement = abs(vec2(0.0, -frameTimeCounter * 0.31365))*0.90;	//make it a bit slower than in vibrant shaders

	coord *= 0.262144;
	vec2 coord0 = coord * rmatrix(1.0) - movement * 4.0;
		 coord0.y *= 3.0;
	vec2 coord1 = coord * rmatrix(0.5) - movement * 1.5;
		 coord1.y *= 3.0;
	
	float wave = 1.0 - texture2D(noisetex,coord0 * 0.005).x * 10.0;		//big waves
		  wave += texture2D(noisetex,coord1 * 0.010416).x * 7.0;		//small waves
		  wave *= 0.0157;
	
	return wave;
}
vec2 calcBump(vec2 coord){
	const vec2 deltaPos = vec2(0.25, 0.0);

	float h0 = calcWaves(coord);
	float h1 = calcWaves(coord + deltaPos.xy);
	float h2 = calcWaves(coord - deltaPos.xy);
	float h3 = calcWaves(coord + deltaPos.yx);
	float h4 = calcWaves(coord - deltaPos.yx);

	float xDelta = ((h1-h0)+(h0-h2));
	float yDelta = ((h3-h0)+(h0-h4));

	return vec2(xDelta,yDelta)*0.05;
}
#endif

#ifdef Celshading
float pw = 1.0/ viewWidth;
float ph = 1.0/ viewHeight;
float getdepth(vec2 coord) {
	return texture2D(depthtex0,coord).x;
}
vec3 celshade(vec3 c) {
	//edge detect
	float dtresh = 1/(far-near)* 0.0005;
	vec4 dc = vec4(getdepth(texcoord.xy));

	vec4 sa = vec4(getdepth(texcoord.xy + vec2(-pw,-ph)),
				   getdepth(texcoord.xy + vec2(pw,-ph)),
				   getdepth(texcoord.xy + vec2(-pw,0.0)),
				   getdepth(texcoord.xy + vec2(0.0,ph)));
	
	//opposite side samples
	vec4 sb = vec4(getdepth(texcoord.xy + vec2(pw,ph)),
				   getdepth(texcoord.xy + vec2(-pw,ph)),
				   getdepth(texcoord.xy + vec2(pw,0.0)),
				   getdepth(texcoord.xy + vec2(0.0,-ph)));

	vec4 dd = abs(2.0* dc - sa - sb) - dtresh;
		 dd = step(dd.xyzw, vec4(0.0));

	float e = clamp(dot(dd,vec4(0.25f)),0.0,1.0);
	return c*e;
}
#endif

#ifdef Godrays
varying vec2 lightPos;
float land = 1.0-near/far/far;
float getnoise(vec2 pos) {
	return fract(sin(dot(pos ,vec2(18.9898f,28.633f))) * 4378.5453f);
}
vec3 calcRays(vec3 color){
	vec2 deltatexcoord = vec2(lightPos - texcoord) * 0.04;
	#if grays_quality == 1
		vec2 noisetc = texcoord; //fast unfiltered
	#elif grays_quality == 2
		vec2 noisetc = texcoord + deltatexcoord*getnoise(texcoord); //slow filtered
	#endif
	#ifndef DISTANT_HORIZONS
		float gr = 1.0;
		for (int i = 0; i < 20; i++) {
			float depth0 = texture2D(depthtex0, noisetc).x;
			noisetc += deltatexcoord;
			gr += dot(step(land, depth0), 1.0)*cdist(noisetc);
		}
		gr /= 20.0;
		float lightpos = clamp(dot(normalize(toScreenSpace(vec3(texcoord.xy, texture2D(depthtex0, texcoord.xy).x))), normalize(shadowLightPosition.xyz)), 0.0, 1.0)*gr*grays_intensity;
	#else
		float DHland = 1.0-dhNearPlane/dhFarPlane/dhFarPlane;
		float gr = 1.0;
		for (int i = 0; i < 20; i++) {
			float DHdepth = texture2D(dhDepthTex0, noisetc).x;
				  DHdepth *= texture2D(depthtex0, noisetc).x;
			noisetc += deltatexcoord;
			gr += dot(step(DHland, DHdepth), 1.0)*cdist(noisetc);
		}
		gr /= 20.0;
		float lightpos = clamp(dot(normalize(nvec3(dhProjectionInverse * (vec4(texcoord.xy, DHdepth0, 1.0) * 2.0 - 1.0))), normalize(shadowLightPosition.xyz)), 0.0, 1.0)*gr*grays_intensity;
	#endif
	return color *= 1.0+lightpos*color * (1.0 - isEyeInWater);
}
#endif

#ifdef skyReflection
uniform vec3 skyColor;
#endif

void main() {

	vec4 tex = texture2D(texture, texcoord.xy)*color;
	vec3 normal = texture2D(gnormal, texcoord.xy).xyz; //vec2 for normals, z=mat
	vec3 newnormal = decode(normal.xy);
	vec3 fragPos = toScreenSpace(vec3(texcoord, texture2D(depthtex0, texcoord.xy).x));

	float getmat = normal.z*2.0;
	//bool iswater = getmat > 0.9 && getmat < 1.1;
	bool isreflective = getmat > 0.9 && getmat < 2.1;
	bool isice = getmat > 1.9 && getmat < 2.1;
	bool iswaterlavasnow = (isEyeInWater == 1.0 || isEyeInWater == 2.0 || isEyeInWater == 3.0);

#ifdef SSAO
	vec3 ao_normal = normalize(cross(dFdx(fragPos),dFdy(fragPos)));
	if(!iswaterlavasnow)tex.rgb *= mix(calcSSDO(fragPos, ao_normal), 1.0, 1.0-exp(-length(fragPos)/(0.2*far-near)));	//set an offset and scale ao with render distance
#endif

#ifdef Celshading	
	if(!isreflective)tex.rgb = mix(celshade(tex.rgb), tex.rgb, 1.0-exp(-length(fragPos)/(0.3*far-near)));	//set an offset and scale celshading with render distance
#endif

#ifdef Reflections
if(isreflective && isEyeInWater < 0.9){
	#ifdef skyReflection
		vec3 finalskyC = mix(tex.rgb, skyColor.rgb, clamp((eyeBrightnessSmooth.y/255.0-2.0/16.0)*1.5,0.0,1.0)); //change skycolor to texcolor in low light areas to prevent day/night issues.
		vec4 relfcolor = vec4(finalskyC*0.75, 1.0);
	#else
		vec4 relfcolor = tex;
	#endif	
	vec4 reflection = raytrace(relfcolor, newnormal.xyz);	
	//tex.rgb = mix(tex.rgb, reflection.rgb, tex.a*reflection.a);

 	vec3 normfrag1 = normalize(toScreenSpace(vec3(texcoord.xy, texture2D(depthtex1, texcoord.xy).x)));
	#ifdef DISTANT_HORIZONS
		if(DH_reflective) { normfrag1 = normalize(nvec3(dhProjectionInverse * (vec4(texcoord.xy, DHdepth1, 1.0) * 2.0 - 1.0))); fragPos = nvec3(dhProjectionInverse * (vec4(texcoord, DHdepth0, 1.0) * 2.0 - 1.0)); }
	#endif
	vec3 rVector = reflect(normfrag1, normalize(newnormal.xyz));
	vec3 hV= normalize(rVector - normfrag1);
	
	float normalDotEye = dot(hV, normfrag1);
	float F0 = 0.09;
	float fresnel = pow(clamp(1.0 + normalDotEye,0.0,1.0), 4.0) ;
		  fresnel = fresnel+F0*(1.0-fresnel);
		
	#ifdef Refractions
		vec2 wpos = (gbufferModelViewInverse*vec4(fragPos,1.0)).xz+cameraPosition.xz;
		if(!isice)tex.rgb = texture2D(texture, (texcoord.xy+calcBump(wpos))).rgb*color.rgb;
	#endif

	reflection.rgb = mix(relfcolor.rgb, reflection.rgb, reflection.a); //maybe change tex with skycolor
	tex.rgb = mix(tex.rgb, reflection.rgb, fresnel*1.25);
	#ifdef Fog
    	float newFar = far;
		float dist = length(fragPos);
		#ifdef DISTANT_HORIZONS
   		 	newFar = max(far, float(dhRenderDistance * 16.0));
		#endif 
		#ifdef VOXY
    		newFar = max(far, float(vxRenderDistance * 16.0));
		#endif
   		#if defined(IS_IRIS) || MC_VERSION >= 11802	//optifine added fog uniforms in 1.18.2, slight offset for reflections 12.5 - 11.5 -> 10.5 - 9.5
   		 	tex.rgb = mix(tex.rgb, fogColor, clamp(max((dist - fogStart) / max(fogEnd - fogStart, 0.0001), dist / newFar * 10.5 - 9.5), 0.0, 1.0));
		#else
    		tex.rgb = mix(tex.rgb, gl_Fog.color.rgb, (isEyeInWater > 0.9) ? clamp(1.0 - exp(-dist * gl_Fog.density), 0.0, 1.0) : clamp(max((dist - gl_Fog.start) / max(gl_Fog.end - gl_Fog.start, 0.0001), dist / newFar * 10.5 - 9.5), 0.0, 1.0));
		#endif
	#endif
}
#endif

#ifdef Godrays
	tex.rgb = calcRays(tex.rgb);
#endif

#ifdef depthbuffer
float c = (2.0 * near) / (far + near - texture2D(depthtex0, texcoord.xy).x * (far - near));  //convert to linear values 
tex.rgb = vec3(c);
#endif

#ifdef draw_refnormals
tex.rgb = normal.rgb;
#endif

	gl_FragData[0] = tex;
	gl_FragData[1] = vec4(0.0); //improves performance
}
