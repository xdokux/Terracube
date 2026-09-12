#version 130

// Shader by LoLip_p

#include "distort.glsl"
#include "/settings.glsl"

in vec2 TexCoords;

uniform float far;
uniform vec3 sunPosition;
uniform float rainStrength;
uniform int worldTime;
uniform vec3 shadowLightPosition;
uniform vec3 playerPosition;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform sampler2D noisetex;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

/*
const int colortex0Format = R11F_G11F_B10F;
const int colortex2Format = RGB8;
const int colortex3Format = RG16;
const int colortex4Format = RGBA2;
const int colortex5Format = R8;
const int colortex6Format = R8;
const int colortex7Format = R8;
*/

float state;

float smoothTransition(float time) {
    if (time >= 0.0f && time <= 1000.0f) {
        return time / 1000.0f; // Transition from 0 to 1
    } else if (time > 1000.0f && time < 12000.0f) {
        return 1.0f; // Fully enabled
    } else if (time >= 12000.0f && time <= 13000.0f) {
        return 1.0f - (time - 12000.0f) / 1000.0f; // Transition from 1 to 0
    } else {
        return 0.0f; // Fully disabled
    }
}

const vec3 MOD3 = vec3(.1031,.11369,.13787);
float hash12(vec2 p)
{
	vec3 p3  = fract(vec3(p.xyx) * MOD3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

#if ENABLE_SHADOW == 1
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

float swapDayNight(float time) {
    if (time >= 12300.0f && time <= 12800.0f) {
        return (time - 12300.0f) / 500.0f; // Плавный переход от 0 до 1
    } else if (time > 12800.0f && time <= 13200.0f) {
        return 1.0f - (time - 12800.0f) / 400.0f; // Плавный переход от 1 до 0
    } else if (time >= 22700.0f && time <= 23200.0f) {
        return (time - 22700.0f) / 500.0f; // Плавный переход от 0 до 1
    } else if (time > 23200.0f && time <= 23700.0f) {
        return 1.0f - (time - 23200.0f) / 500.0f; // Плавный переход от 1 до 0
    } else {
        return 0.0f; // Вне указанных диапазонов
    }
}

float calculateShadowBias(float distance) {
	float bias = 0.0001f;
	#if PIXEL_SHADOW > 0
	bias = 0.0005f;
	#endif
    return mix(bias, 0.003f, clamp(distance / shadowDistance, 0.0f, 1.0f));
}

float Visibility(in sampler2D ShadowMap, in vec3 SampleCoords, in vec3 WorldPosition) {
	float distance = length(WorldPosition - playerPosition);
    float bias = calculateShadowBias(distance);
	
    return step(SampleCoords.z - bias, texture2D(ShadowMap, SampleCoords.xy).r);
}

vec3 TransparentShadow(in vec3 SampleCoords, in vec3 WorldPosition){
    float ShadowVisibility0 = Visibility(shadowtex0, SampleCoords, WorldPosition);
    float ShadowVisibility1 = Visibility(shadowtex1, SampleCoords, WorldPosition);
    vec4 ShadowColor0 = texture2D(shadowcolor0, SampleCoords.xy);
    vec3 TransmittedColor = ShadowColor0.rgb * (1.0f - ShadowColor0.a);
    return mix(TransmittedColor * ShadowVisibility1, vec3(1.0f), ShadowVisibility0);
}

const int ShadowSamplesPerSize = 2 * SOFT + 1;
const int TotalSamples = ShadowSamplesPerSize * ShadowSamplesPerSize;

vec3 GetShadow(float depth) {
    vec3 ClipSpace = vec3(TexCoords, depth) * 2.0f - 1.0f;
	
    vec4 ViewW = gbufferProjectionInverse * vec4(ClipSpace, 1.0f);
    vec3 View = ViewW.xyz / ViewW.w;
	
    vec4 World = gbufferModelViewInverse * vec4(View, 1.0f);
	
	#if PIXEL_SHADOW > 0
	World.xyz = (floor((World.xyz + cameraPosition) * PIXEL_SHADOW + 0.01) + 0.5) / PIXEL_SHADOW - cameraPosition;
	#endif
	
    vec4 ShadowSpace = shadowProjection * shadowModelView * World;
    ShadowSpace.xyz = DistortPosition(ShadowSpace.xyz);
    vec3 SampleCoords = ShadowSpace.xyz * 0.5f + 0.5f;
	
	float RandomAngle = hash12((TexCoords + frameTimeCounter) * 100);
    //float RandomAngle = texture2D(noisetex,  (TexCoords + vec2(0.1, 0.2) + vec2(sin(frameTimeCounter), cos(frameTimeCounter)) * 0.0005) * 32).r * 100.0f;
    float cosTheta = cos(RandomAngle);
	float sinTheta = sin(RandomAngle);
    mat2 Rotation =  mat2(cosTheta, -sinTheta, sinTheta, cosTheta) / shadowMapResolution; // We can move our division by the shadow map resolution here for a small speedup
    vec3 ShadowAccum = vec3(0.0f);
    for(int x = -SOFT; x <= SOFT; x++){
		for(int y = -SOFT; y <= SOFT; y++){
			vec2 Offset = Rotation * vec2(x, y);
			vec3 CurrentSampleCoordinate = vec3(SampleCoords.xy + Offset, SampleCoords.z);
		
			CurrentSampleCoordinate = clamp(CurrentSampleCoordinate, 0.0, 1.0); // clamp
		
			ShadowAccum += TransparentShadow(CurrentSampleCoordinate, World.xyz);
		}
    }
    ShadowAccum /= TotalSamples;
	
	float distanceShadowFade = length(View) / shadowDistance;
	float shadowFade = smoothstep(0.0, 1.0, 1.0 - distanceShadowFade);

	ShadowAccum = clamp(mix(vec3(1), ShadowAccum, 1 - pow(1 - shadowFade, 10)), 0, 1);

    return ShadowAccum;
}
#endif

float AdjustLightmapTorch(in float torchLight) {
    const float K = 1.75f;
	const float P = 3.0f;
    return K * pow(torchLight, P);
}

float AdjustLightmapSky(in float sky){
    float sky_2 = sky * sky;
    return sky_2 * sky_2;
}

vec2 AdjustLightmap(in vec2 Lightmap){
    vec2 NewLightMap;
    NewLightMap.x = AdjustLightmapTorch(Lightmap.x);
    NewLightMap.y = AdjustLightmapSky(Lightmap.y);
    return NewLightMap;
}

vec3 GetLightmapColor(in vec2 Lightmap){
    Lightmap = AdjustLightmap(Lightmap);
    vec3 SkyColor = vec3(0.05f, 0.15f, 0.3f);
	
	#if ENABLE_SHADOW == 0
	SkyColor = vec3(1) * 0.1f;
	#endif
	
    vec3 TorchLighting = Lightmap.x * vec3(1.0f);
    vec3 SkyLighting = Lightmap.y * SkyColor * state * (1 - rainStrength);
	
	//TorchLighting -= (Lightmap.y * LIGHT_ABSORPTION * state * (1 - rainStrength));
	
	float occ = (Lightmap.y * LIGHT_ABSORPTION * state * (1 - rainStrength));
	float torchMask = smoothstep(-0.2, 0.8, Lightmap.x);
	TorchLighting -= occ * torchMask;
	
	vec3 LightmapLighting = clamp(TorchLighting * vec3(1.0f, 0.85f, 0.7f), 0.0f, 1.0f) + SkyLighting;
	
    return LightmapLighting;
}

uniform float viewWidth, viewHeight;

#if AO == 1
const float BIAS = 0.05;

vec3 getPosition(vec2 uv) {
    float z = texture2D(depthtex0, uv).r;
	vec2 ndc = uv * 2.0 - 1.0;
	vec4 clip = vec4(ndc, z * 2.0 - 1.0, 1.0);
	vec4 view = gbufferProjectionInverse * clip;
	view /= view.w;
	return view.xyz;
}

vec3 getNormal(vec2 uv) {
    vec3 n = texture2D(colortex4, uv).xyz * 2.0 - 1.0;
    return normalize(n);
}

// Sample one AO ray
float doAO(vec2 uv, vec2 dir, vec3 p, vec3 n) {
    vec3 samplePos = getPosition(uv + dir) - p;
    float dist = length(samplePos);
    vec3  v    = samplePos / dist;
    float d    = dist * SCALE;
    float ao   = max(dot(n, v) - BIAS, 0.0) / (1.0 + d);
    ao *= smoothstep(MAX_DISTANCE, MAX_DISTANCE * 0.5, dist);
    return ao;
}

// Spiral-pattern AO
float spiralAO(vec2 uv, vec3 p, vec3 n, float rad) {
    const float golden = 2.4; // ≈ π*(3 - √5)
    float ao = 0.0;
    float inv = 1.0 / float(SAMPLES);
	float radius = 0.0;
    float phase = hash12((uv + frameTimeCounter) * 100.0) * 6.28;
    float step = rad * inv;
	
    for (int i = 0; i < SAMPLES; i++) {
        vec2 dir = vec2(sin(phase), cos(phase));
		radius += step;
        phase += golden;
        ao += doAO(uv, dir * radius, p, n);
    }
    return ao * inv;
}
#endif

uniform int isEyeInWater;
uniform float near;
uniform float blindness;
uniform float darknessFactor;
uniform vec3 fogColor;

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position){
	vec4 homPos = projectionMatrix * vec4(position, 1.0);
	return homPos.xyz / homPos.w;
}

void main(){
	vec3 Albedo = pow(texture2D(colortex0, TexCoords).rgb, vec3(2.2f));
	
	float Depthv1 = texture2D(depthtex0, TexCoords).r;
    if(Depthv1 == 1.0f) {
		/* DRAWBUFFERS:06 */
        gl_FragData[0].rgb = Albedo;
        gl_FragData[1].r = 1.0f;
        return;
    }
	
	float Depthv2 = texture2D(depthtex1, TexCoords).r;
	float normal = texture2D(colortex3, TexCoords).x;
	vec3 lightBrightnessV = vec3(1.0);
    vec3 ShadowColor = vec3(1);
	vec3 NdotL = vec3(1);
	
	vec2 Lightmap = texture2D(colortex2, TexCoords).rg;
	state = smoothTransition(worldTime);
	vec3 LightmapColor = GetLightmapColor(Lightmap);
	
	#if SHADING == 1
	float lightBrightness = texture2D(colortex2, TexCoords).z;
	
	lightBrightness *= state;
	lightBrightness *= 1.0f - rainStrength;
	lightBrightness += (rainStrength - 0.5f) * (1.0f - state) * rainStrength; //Rain
	lightBrightnessV = vec3(lightBrightness) * state;
	lightBrightnessV += (vec3(0.0, 0.0, 0.5))* (1.0f - state); //Night
	#endif
	
	lightBrightnessV *= AdjustLightmap(Lightmap).g;
	lightBrightnessV += 0.2f * ((1.0f - state) + rainStrength * state);
	
	#if FOG == 1
	vec3 NDCPos = vec3(TexCoords, Depthv1) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
	
	float farW = far;
	float distW = FOG_DISTANCE;
	
	if(isEyeInWater == 1) {
		farW = 64;
		distW = 4;
	}
	
	float distance = length(viewPos) / (farW * mix(mix(1, near * 0.5, blindness), near, darknessFactor));
	float fogFactor = exp(-mix(distW, 1, blindness) * (1.0 - distance));
	
	if(Depthv2 == 1 && normal == 0) {
		/*DRAWBUFFERS:06*/
		gl_FragData[0].rgb = Albedo;
		gl_FragData[1].r = 1.0f;
		return;
	}
	#endif
	
	if(normal > 0.002f) {
		#if ENABLE_SHADOW == 1
		vec3 originalShadow = GetShadow(Depthv1);
		float shadow_transperency_coef = mix(0.3, SHADOW_TRANSPARENCY, state);
		ShadowColor = mix(originalShadow * vec3(shadow_transperency_coef / 0.75), originalShadow, state);
		ShadowColor = mix(ShadowColor, vec3(1), swapDayNight(worldTime));
		vec3 colorRainDayOrNight = mix(vec3(0.2), vec3(1), smoothTransition(worldTime));
		ShadowColor = mix(ShadowColor, colorRainDayOrNight, rainStrength);
	
		ShadowColor *= AdjustLightmap(Lightmap).g;
		ShadowColor += shadow_transperency_coef;
		#endif
		
		LightmapColor *= mix(5, 1, state);
		lightBrightnessV *= mix(2.5f, 1.0f, state);
		
		Albedo *= clamp(state, SHADOW_TRANSPARENCY + 0.1, 1.0f);
		Albedo *= (LightmapColor + lightBrightnessV * ShadowColor);
		
		#if FOG == 1
		Albedo = mix(Albedo, pow(fogColor, vec3(2.2f)), clamp(fogFactor, 0.0, 1.0));
		#endif
		
		/* DRAWBUFFERS:06 */
		gl_FragData[0].rgb = Albedo;
		gl_FragData[1].r = 1.0f;
		return;
    }

	float ao = 1.0;
	
	#if AO == 1
	if(isEyeInWater != 1 && isEyeInWater != 2) {
		vec2 ndc = TexCoords * 2.0 - 1.0;
		vec4 clip = vec4(ndc, Depthv1 * 2.0 - 1.0, 1.0);
		vec4 view = gbufferProjectionInverse * clip;
		view /= view.w;
		
		float distanceFade = clamp(length(view.xyz) / (far / 1.5), 0.0, 1.0);
		float fade = pow(smoothstep(0.0, 1.0, 1.0 - distanceFade), 0.25);
		
		if (fade > 0.15) { // Отсекаем очень дальние пиксели
			vec3 p = getPosition(TexCoords);
			vec3 n = getNormal(TexCoords);
			float rad = SAMPLE_RAD / abs(p.z);
			
			float rawAO = spiralAO(TexCoords, p, n, rad);
			float aoStrength = 1.0 - rawAO * INTENSITY;
			ao = mix(1.0, aoStrength, fade); // плавное применение AO
		}
	}
	#endif

	float shadow_transperency_coef = mix(0.3, SHADOW_TRANSPARENCY, state);
	
	#if ENABLE_SHADOW == 1
	if (float(Depthv1 < 0.56) < 0.5) {
		vec3 originalShadow = GetShadow(texture2D(depthtex1, TexCoords).r);
		ShadowColor = mix(originalShadow * vec3(shadow_transperency_coef / 0.75), originalShadow, state);
		ShadowColor = mix(ShadowColor, vec3(1), swapDayNight(worldTime));
		vec3 colorRainDayOrNight = mix(vec3(0.2), vec3(1), smoothTransition(worldTime));
		ShadowColor = mix(ShadowColor, colorRainDayOrNight, rainStrength);
		
		ShadowColor *= AdjustLightmap(Lightmap).g;
	}
	else
	{
		ao = 1;
	}
	#endif
	
	ShadowColor *= mix(vec3(1.0f), lightBrightnessV, state);
	ShadowColor += shadow_transperency_coef;
	ShadowColor *= mix(lightBrightnessV, vec3(1.0f), state);
	
	vec3 Diffuse = Albedo * (LightmapColor + ShadowColor);
	Diffuse = clamp(Diffuse, 0, 1);
	
	#if FOG == 1
	Diffuse = mix(Diffuse, pow(fogColor, vec3(2.2f)), clamp(fogFactor, 0.0, 1.0));
	#endif
	
	/* DRAWBUFFERS:06 */
    gl_FragData[0].rgb = Diffuse;
    gl_FragData[1].r = ao;
}
