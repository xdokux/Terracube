#version 120
/* DRAWBUFFERS:3 */
/*
Sildur's Basic Shaders:
https://www.patreon.com/Sildur
https://sildurs-shaders.github.io/
https://twitter.com/SildurFX

Permissions:
You are not allowed to edit, copy code or share my shaderpack under a different name or claim it as yours.
*/

#define AA
#define composite0
#include "shaders.settings"

varying vec4 color;
varying vec2 texcoord;
uniform sampler2D colortex0;

#if defined TAA || defined SSAO || defined Celshading || defined depthbuffer
uniform float near;
uniform float far;
uniform float viewHeight;
uniform float viewWidth;
uniform sampler2D depthtex0;
vec2 texelSize = vec2(1.0/viewWidth,1.0/viewHeight);

uniform mat4 gbufferProjectionInverse;
vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = p * 2.0 - 1.0;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}
#endif

#ifdef TAA
const bool colortex3Clear = false;
uniform sampler2D colortex3;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

#define BLEND_FACTOR 0.1 			//[0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.1 0.12 0.14 0.16] higher values = more flickering but sharper image, lower values = less flickering but the image will be blurrier
#define MOTION_REJECTION 1.0		//[0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.5] //Higher values=sharper image in motion at the cost of flickering
#define ANTI_GHOSTING 0.0			//[0.0 0.25 0.5 0.75 1.0] High values reduce ghosting but may create flickering
#define FLICKER_REDUCTION 1.0		//[0.0 0.25 0.5 0.75 1.0] High values reduce flickering but may reduce sharpness

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

vec3 toClipSpace3Prev(vec3 viewSpacePosition) {
    return projMAD(gbufferPreviousProjection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5;
}

//returns the projected coordinates of the closest point to the camera in the 3x3 neighborhood
vec3 closestToCamera5taps(vec2 texcoord){
	vec2 du = vec2(texelSize.x*2., 0.0);
	vec2 dv = vec2(0.0, texelSize.y*2.);

	vec3 dtl = vec3(texcoord,0.) + vec3(-texelSize, texture2D(depthtex0, texcoord - dv - du).x);
	vec3 dtr = vec3(texcoord,0.) +  vec3( texelSize.x, -texelSize.y, texture2D(depthtex0, texcoord - dv + du).x);
	vec3 dmc = vec3(texcoord,0.) + vec3( 0.0, 0.0, texture2D(depthtex0, texcoord).x);
	vec3 dbl = vec3(texcoord,0.) + vec3(-texelSize.x, texelSize.y, texture2D(depthtex0, texcoord + dv - du).x);
	vec3 dbr = vec3(texcoord,0.) + vec3( texelSize.x, texelSize.y, texture2D(depthtex0, texcoord + dv + du).x);

	vec3 dmin = dmc;
	dmin = dmin.z > dtr.z? dtr : dmin;
	dmin = dmin.z > dtl.z? dtl : dmin;
	dmin = dmin.z > dbl.z? dbl : dmin;
	dmin = dmin.z > dbr.z? dbr : dmin;
	return dmin;
}

//approximation from SMAA presentation from siggraph 2016
vec3 FastCatmulRom(sampler2D colorTex, vec2 texcoord, vec4 rtMetrics, float sharpenAmount){
    vec2 position = rtMetrics.zw * texcoord;
    vec2 centerPosition = floor(position - 0.5) + 0.5;
    vec2 f = position - centerPosition;
    vec2 f2 = f * f;
    vec2 f3 = f * f2;

    float c = sharpenAmount;
    vec2 w0 =        -c  * f3 +  2.0 * c         * f2 - c * f;
    vec2 w1 =  (2.0 - c) * f3 - (3.0 - c)        * f2         + 1.0;
    vec2 w2 = -(2.0 - c) * f3 + (3.0 -  2.0 * c) * f2 + c * f;
    vec2 w3 =         c  * f3 -                c * f2;

    vec2 w12 = w1 + w2;
    vec2 tc12 = rtMetrics.xy * (centerPosition + w2 / w12);
    vec3 centerColor = texture2D(colorTex, vec2(tc12.x, tc12.y)).rgb;

    vec2 tc0 = rtMetrics.xy * (centerPosition - 1.0);
    vec2 tc3 = rtMetrics.xy * (centerPosition + 2.0);
    vec4 color = vec4(texture2D(colorTex, vec2(tc12.x, tc0.y )).rgb, 1.0) * (w12.x * w0.y ) +
                   vec4(texture2D(colorTex, vec2(tc0.x,  tc12.y)).rgb, 1.0) * (w0.x  * w12.y) +
                   vec4(centerColor,                                      1.0) * (w12.x * w12.y) +
                   vec4(texture2D(colorTex, vec2(tc3.x,  tc12.y)).rgb, 1.0) * (w3.x  * w12.y) +
                   vec4(texture2D(colorTex, vec2(tc12.x, tc3.y )).rgb, 1.0) * (w12.x * w3.y );
	return color.rgb/color.a;

}

vec3 calcTAA(vec3 albedoCurrent0){
	//reproject previous frame
	vec3 closestToCamera = closestToCamera5taps(texcoord);
	vec3 fragposition = toScreenSpace(closestToCamera);
		 fragposition = mat3(gbufferModelViewInverse) * fragposition + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition);
	vec3 previousPosition = mat3(gbufferPreviousModelView) * fragposition + gbufferPreviousModelView[3].xyz;
		 previousPosition = toClipSpace3Prev(previousPosition);
		 previousPosition.xy = texcoord + (previousPosition.xy - closestToCamera.xy);

	//to reduce error propagation caused by interpolation during history resampling, we will introduce back some aliasing in motion
	vec2 d = 0.5-abs(fract(previousPosition.xy*vec2(viewWidth,viewHeight)-texcoord*vec2(viewWidth,viewHeight))-0.5);
	float rej = dot(d,d)*MOTION_REJECTION;
	//reject history if off-screen and early exit
	if (previousPosition.x < 0.0 || previousPosition.y < 0.0 || previousPosition.x > 1.0 || previousPosition.y > 1.0) return texture2D(colortex0, texcoord).rgb;

  	vec3 albedoCurrent1 = texture2D(colortex0, texcoord + vec2(texelSize.x,texelSize.y)).rgb;
	vec3 albedoCurrent2 = texture2D(colortex0, texcoord + vec2(texelSize.x,-texelSize.y)).rgb;
	vec3 albedoCurrent3 = texture2D(colortex0, texcoord + vec2(-texelSize.x,-texelSize.y)).rgb;
	vec3 albedoCurrent4 = texture2D(colortex0, texcoord + vec2(-texelSize.x,texelSize.y)).rgb;
	vec3 albedoCurrent5 = texture2D(colortex0, texcoord + vec2(0.0,texelSize.y)).rgb;
	vec3 albedoCurrent6 = texture2D(colortex0, texcoord + vec2(0.0,-texelSize.y)).rgb;
	vec3 albedoCurrent7 = texture2D(colortex0, texcoord + vec2(-texelSize.x,0.0)).rgb;
	vec3 albedoCurrent8 = texture2D(colortex0, texcoord + vec2(texelSize.x,0.0)).rgb;	

	if(TAA_sharpness > 0.0){	//turn sharpening off if set to 0.0
    vec3 m1 = (albedoCurrent0 + albedoCurrent1 + albedoCurrent2 + albedoCurrent3 + albedoCurrent4 + albedoCurrent5 + albedoCurrent6 + albedoCurrent7 + albedoCurrent8)/9.0;
    vec3 std = abs(albedoCurrent0 - m1) + abs(albedoCurrent1 - m1) + abs(albedoCurrent2 - m1) + abs(albedoCurrent3 - m1) + abs(albedoCurrent3 - m1) + 
			   abs(albedoCurrent4 - m1) + abs(albedoCurrent5 - m1) + abs(albedoCurrent6 - m1) + abs(albedoCurrent7 - m1) + abs(albedoCurrent8 - m1);

    float contrast = 1.0 - dot(std,vec3(0.299, 0.587, 0.114))/9.0;
    albedoCurrent0 = albedoCurrent0*(1.0+TAA_sharpness*contrast)-(albedoCurrent5+albedoCurrent6+albedoCurrent7+albedoCurrent8+(albedoCurrent1 + albedoCurrent2 + albedoCurrent3 + albedoCurrent4)/2.0)/6.0*TAA_sharpness*contrast;
	}

	//Assuming the history color is a blend of the 3x3 neighborhood, we clamp the history to the min and max of each channel in the 3x3 neighborhood
	vec3 cMax = max(max(max(albedoCurrent0,albedoCurrent1),albedoCurrent2),max(albedoCurrent3,max(albedoCurrent4,max(albedoCurrent5,max(albedoCurrent6,max(albedoCurrent7,albedoCurrent8))))));
	vec3 cMin = min(min(min(albedoCurrent0,albedoCurrent1),albedoCurrent2),min(albedoCurrent3,min(albedoCurrent4,min(albedoCurrent5,min(albedoCurrent6,min(albedoCurrent7,albedoCurrent8))))));

	vec3 albedoPrev = FastCatmulRom(colortex3, previousPosition.xy,vec4(texelSize, 1.0/texelSize), 0.82).xyz;

	vec3 finalcAcc = clamp(albedoPrev,cMin,cMax);

	//increases blending factor if history is far away from aabb, reduces ghosting at the cost of some flickering
	float luma = dot(albedoPrev,vec3(0.21, 0.72, 0.07));
	float isclamped = distance(albedoPrev,finalcAcc)/luma;

	//reduces blending factor if current texel is far from history, reduces flickering
	float lumDiff2 = distance(albedoPrev,albedoCurrent0)/luma;
	lumDiff2 = 1.0-clamp(lumDiff2*lumDiff2,0.0,1.0)*FLICKER_REDUCTION;

	//Blend current pixel with clamped history
	return mix(finalcAcc,albedoCurrent0,clamp(BLEND_FACTOR*lumDiff2+rej+isclamped*ANTI_GHOSTING+0.01,0.0,1.0));
}
#endif

#if defined SSAO || defined Celshading
uniform sampler2D colortex2;
#endif

#ifdef SSAO
uniform int isEyeInWater;
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

#ifdef Celshading
float getdepth(vec2 coord) {
	return texture2D(depthtex0,coord).x;
}
vec3 celshade(vec3 c) {
	//edge detect
	float dtresh = 1/(far-near)* 0.0005;
	vec4 dc = vec4(getdepth(texcoord.xy));

	vec4 sa = vec4(getdepth(texcoord.xy + vec2(-texelSize.x,-texelSize.y)),
				   getdepth(texcoord.xy + vec2(texelSize.x,-texelSize.y)),
				   getdepth(texcoord.xy + vec2(-texelSize.x,0.0)),
				   getdepth(texcoord.xy + vec2(0.0,texelSize.y)));
	
	//opposite side samples
	vec4 sb = vec4(getdepth(texcoord.xy + vec2(texelSize.x,texelSize.y)),
				   getdepth(texcoord.xy + vec2(-texelSize.x,texelSize.y)),
				   getdepth(texcoord.xy + vec2(texelSize.x,0.0)),
				   getdepth(texcoord.xy + vec2(0.0,-texelSize.y)));

	vec4 dd = abs(2.0* dc - sa - sb) - dtresh;
		 dd = step(dd.xyzw, vec4(0.0));

	float e = clamp(dot(dd,vec4(0.25f)),0.0,1.0);
	return c*e;
}
#endif

void main() {

	vec3 tex = texture2D(colortex0, texcoord).rgb*color.rgb;
	
	#if defined SSAO || defined Celshading
	float normalMats = texture2D(colortex2, texcoord.xy).z;
	vec3 fragPos = toScreenSpace(vec3(texcoord, texture2D(depthtex0, texcoord.xy).x));
	float getmat = normalMats*2.0;
	//bool iswater = getmat > 0.9 && getmat < 1.1;
	//bool isice = getmat > 1.9 && getmat < 2.1;
	bool isWaterIce = getmat > 0.9 && getmat < 2.1;
	#endif

	#ifdef SSAO
		bool iswaterlavasnow = (isEyeInWater == 1.0 || isEyeInWater == 2.0 || isEyeInWater == 3.0);
		vec3 ao_normal = normalize(cross(dFdx(fragPos),dFdy(fragPos)));
		if(!iswaterlavasnow) tex *= mix(calcSSDO(fragPos, ao_normal), 1.0, 1.0-exp(-length(fragPos)/(0.2*far-near)));	//set an offset and scale ao with render distance
	#endif

	#ifdef Celshading	
		if(!isWaterIce)tex = mix(celshade(tex), tex, 1.0-exp(-length(fragPos)/(0.3*far-near)));	//set an offset and scale celshading with render distance
	#endif

	#ifdef depthbuffer
		float c = (2.0 * near) / (far + near - texture2D(depthtex0, texcoord.xy).x * (far - near));  //convert to linear values 
		tex = vec3(c);
	#endif

	#ifdef TAA
	gl_FragData[0] = vec4(calcTAA(tex), 1.0);
	#else
	gl_FragData[0] = vec4(tex, 1.0);
	#endif
}
