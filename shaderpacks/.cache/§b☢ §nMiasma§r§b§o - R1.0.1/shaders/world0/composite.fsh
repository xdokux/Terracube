#version 130

#include "distort.glsl"
#include "/settings.glsl"
#include "/lib/whatTime.glsl"

in vec2 TexCoords;

uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D noisetex;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 playerPosition;

uniform int worldTime;
uniform int isEyeInWater;
uniform float far, near;
uniform float blindness;
uniform float rainStrength;
uniform float darknessFactor;
uniform float viewWidth, viewHeight;

const int noiseTextureResolution = 64;


float timeCounter;


vec2 viewR = vec2(viewWidth, viewHeight);
float GetLinearDepth(float depth) {
    return (2.0 * near) / (far + near - depth * (far - near));
}
vec2 darkOutlineOffsets[12] = vec2[12](
    vec2( 1.0, 0.0),
    vec2(-1.0, 1.0),
    vec2( 0.0, 1.0),
    vec2( 1.0, 1.0),
    vec2(-2.0, 2.0),
    vec2(-1.0, 2.0),
    vec2( 0.0, 2.0),
    vec2( 1.0, 2.0),
    vec2( 2.0, 2.0),
    vec2(-2.0, 1.0),
    vec2( 2.0, 1.0),
    vec2( 2.0, 0.0)
);
vec3 ViewToPlayer(vec3 pos) {
    return mat3(gbufferModelViewInverse) * pos + gbufferModelViewInverse[3].xyz;
}
void Outline(inout vec3 color, sampler2D depthtex0, vec2 texcoord) {
    vec2 scale = vec2(0.8 / viewR);

    float z0 = texture2D(depthtex0, texcoord).r;
    float linearZ0 = GetLinearDepth(z0);
    float outline = 1.0;
    float z = linearZ0 * far * 2.0;
    float minZ = 1.0, sampleZA = 0.0, sampleZB = 0.0;
    int sampleCount = 12;

    for (int i = 0; i < sampleCount; i++) {
        vec2 offset = scale * darkOutlineOffsets[i];
        sampleZA = texture2D(depthtex0, texcoord + offset).r;
        sampleZB = texture2D(depthtex0, texcoord - offset).r;
        float sampleZsum = GetLinearDepth(sampleZA) + GetLinearDepth(sampleZB);
        outline *= clamp(1.0 - (z - sampleZsum * far), 0.0, 1.0);
        minZ = min(minZ, min(sampleZA, sampleZB));
    }

    if (outline < 0.909091) {
        vec4 viewPos = gbufferProjectionInverse * (vec4(texcoord, minZ, 1.0) * 2.0 - 1.0);
        viewPos /= viewPos.w;
        float lViewPos = length(viewPos.xyz);
        vec3 playerPos = ViewToPlayer(viewPos.xyz);
        vec3 nViewPos = normalize(viewPos.xyz);

        vec3 newColor = vec3(0.03, 0.025, 0.05);

        vec3 color_with_outlines = mix(color, newColor, 1.0 - outline * 1.1);

        float depth = GetLinearDepth(texture2D(depthtex0, texcoord).r);
        color = mix(color_with_outlines, color, clamp(depth, 0.0, 1.0));
    }
}

float AdjustLightmapTorch(in float torchLight) {
    const float K = 1.75f;
	const float P = 3.0f;
    return K * pow(torchLight, P);
}

float AdjustLightmapSky(in float sky){
    float sky_2 = sky * sky;
    return sky_2 * sky_2;
}

float calculateShadowBias(float distance) {
	float bias = 0.0001f;
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

const int TotalSamples = 9;

vec3 GetShadow(float depth) {
    vec3 ClipSpace = vec3(TexCoords, depth) * 2.0f - 1.0f;
	
    vec4 ViewW = gbufferProjectionInverse * vec4(ClipSpace, 1.0f);
    vec3 View = ViewW.xyz / ViewW.w;
    vec4 World = gbufferModelViewInverse * vec4(View, 1.0f);
	
    vec4 ShadowSpace = shadowProjection * shadowModelView * World;
    ShadowSpace.xyz = DistortPosition(ShadowSpace.xyz);
    vec3 SampleCoords = ShadowSpace.xyz * 0.5f + 0.5f;
	
    float RandomAngle = texture2D(noisetex, TexCoords * 20.0f).r * 100.0f;
    float cosTheta = cos(RandomAngle);
	float sinTheta = sin(RandomAngle);
    mat2 Rotation =  mat2(cosTheta, -sinTheta, sinTheta, cosTheta) / shadowMapResolution;
	
    vec3 ShadowAccum = vec3(0.0f);
    for(int x = -1; x <= 1; x++){
        for(int y = -1; y <= 1; y++){
            vec2 Offset = Rotation * vec2(x, y);
            vec3 CurrentSampleCoordinate = vec3(SampleCoords.xy + Offset, SampleCoords.z);
            ShadowAccum += TransparentShadow(CurrentSampleCoordinate, World.xyz);
        }
    }
    ShadowAccum /= TotalSamples;
	
	float distanceShadowFade = length(View) / shadowDistance;
	float shadowFade = smoothstep(0.0, 1.0, 1.0 - distanceShadowFade);
	ShadowAccum = clamp(mix(vec3(1), ShadowAccum, 1 - pow(1 - shadowFade, 10)), 0, 1);
	
    return ShadowAccum;
}

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position){
	vec4 homPos = projectionMatrix * vec4(position, 1.0);
	return homPos.xyz / homPos.w;
}

void main()
{
	timeCounter = smoothTransition(worldTime);

    vec3 Albedo = texture2D(colortex0, TexCoords).rgb;
    float rain = texture2D(colortex4, TexCoords).r;
	vec3 rainCol = vec3(rain) * mix(vec3(0.73, 0.71, 1), vec3(0.549, 0.827, 0.475), timeCounter);
    float Depth = texture2D(depthtex0, TexCoords).r;
	
    if(Depth == 1.0f) {
        gl_FragData[0] = vec4(Albedo+rainCol, 1.0f);
        return;
    }
	
	float lightBrightness = texture2D(colortex3, TexCoords).x;
	vec2 Lightmap = texture2D(colortex3, TexCoords).yz;
	lightBrightness *= mix(AdjustLightmapSky(Lightmap.y) * 0.35f, AdjustLightmapSky(Lightmap.y), timeCounter);
	
	Albedo *= mix(vec3(0.73, 0.71, 1)*0.65f, vec3(1), timeCounter);		//Night Color
    vec3 Diffuse = Albedo * (mix(vec3(1.0f), GetShadow(Depth) * lightBrightness, mix(mix(0.65f, 0.5f, timeCounter), 0, rainStrength)));	//Shadow
	Diffuse *= mix(1, 0.5, rainStrength);
	Diffuse *= mix(1.0, clamp(Lightmap.y + Lightmap.x, 0, 1) + (pow(Lightmap.x, 3)*3f * (1 - timeCounter)), 0.75f);		//Power Light
	
	Outline(Diffuse.rgb, depthtex0, TexCoords);
	
	float farW = far;
	float distW = 3;
	if(isEyeInWater == 1) {
		farW = 32;
		distW = 1;
	}
	vec3 NDCPos = vec3(TexCoords, Depth) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
	float distance = length(viewPos) / (farW * mix(mix(1, near * 0.5, blindness), near, darknessFactor));
	float fogFactor = exp(-mix(distW, 1, blindness) * (1.0 - distance));
	
	// FOG
	Diffuse = mix(Diffuse, mix(vec3(0.549, 0.827, 0.475) * 0.85f, mix(vec3(0.73, 0.71, 1)*0.35f, vec3(0.231, 0.643, 0.639), timeCounter), 1 - isEyeInWater), clamp(fogFactor, 0.0, 1.0));
	
	Diffuse += rainCol;
	
    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(vec3(Diffuse), 1.0f);
}
