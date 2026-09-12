#version 130

#include "/settings.glsl"

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform sampler2D depthtex0;
uniform sampler2D noisetex;

uniform float viewHeight;
uniform float viewWidth;

uniform vec4 entityColor;
uniform float blindness;
uniform int isEyeInWater;
uniform float rainStrength;
uniform int worldTime;
uniform vec3 fogColor;
uniform float dhNearPlane;
uniform float dhFarPlane;

uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;

in vec4 color;
in vec2 TexCoords;
in vec2 LightmapCoords;
in vec3 viewSpaceGeoNormal;
in vec3 playerPos;

lowp float state;

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

float AdjustLightmapTorch(in float torchLight) {
    const float K = 2.0f;
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
    lowp vec3 SkyColor = vec3(0.09f, 0.17f, 0.3f);
	
	#if ENABLE_SHADOW == 0
	SkyColor = vec3(1) * 0.1f;
	#endif
	
    lowp vec3 TorchLighting = Lightmap.x * vec3(1.0f, 1.0f, 1.0f);
    lowp vec3 SkyLighting = Lightmap.y * SkyColor * state * (1 - rainStrength);
	
	TorchLighting -= (Lightmap.y * LIGHT_ABSORPTION * state * (1 - rainStrength));
	
	lowp vec3 LightmapLighting = clamp(TorchLighting * vec3(1.0f, 0.85f, 0.7f), 0.0f, 1.0f) + SkyLighting;
	
    return LightmapLighting;
}

float Noise3D(vec3 p) {
    p.z = fract(p.z) * 32.0;
    float iz = floor(p.z);
    float fz = fract(p.z);
    vec2 a_off = vec2(23.0, 29.0) * (iz) / 128.0;
    vec2 b_off = vec2(23.0, 29.0) * (iz + 1.0) / 128.0;
    float a = texture2D(noisetex, p.xy + a_off).r;
    float b = texture2D(noisetex, p.xy + b_off).r;
    return mix(a, b, fz);
}

float max0(float x) {
    return max(x, 0.0);
}

void main()
{
	vec2 texCoord = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
	float depth = texture2D(depthtex0, texCoord).r;
    if (depth != 1.0) {
		discard;
    }

	vec3 shadowLightDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
	vec3 worldGeoNormal = mat3(gbufferModelViewInverse) * viewSpaceGeoNormal;
	float lightBrightness = clamp(dot(shadowLightDir, worldGeoNormal), 0.0, 1.0);
	
	vec3 lightBrightnessV = vec3(0.1);
	lowp vec3 ShadowColor = vec3(1);

	state = smoothTransition(worldTime);
	vec3 LightmapColor = GetLightmapColor(LightmapCoords);

    vec4 col = color * texture2D(texture, TexCoords);
    col.rgb = mix(col.rgb,entityColor.rgb,entityColor.a);
	
	vec3 noisePos = floor((playerPos + cameraPosition) * 4.0 + 0.001) / 32.0;
    float noiseTexture = Noise3D(noisePos) + 0.5;
    float noiseFactor = max0(1.0 - 0.3 * dot(col.rgb, col.rgb));
    col.rgb *= pow(noiseTexture, 0.15 * noiseFactor);
	
	#if SHADING == 1
	lightBrightness *= state;
	lightBrightness *= 1.0f - rainStrength;
	lightBrightness += (rainStrength - 0.5f) * (1.0f - state) * rainStrength;
	lightBrightnessV = vec3(lightBrightness) * state;
	lightBrightnessV += vec3(0.0, 0.0, 0.5) * (1.0f - state);
	lightBrightnessV += mix(0.30f, 0.10f, state);
	lightBrightnessV = pow(lightBrightnessV, vec3(1.0f / 2.2f));
	lightBrightnessV *= AdjustLightmap(LightmapCoords).g;
	#else
	lightBrightnessV = pow(lightBrightnessV, vec3(1.0f / 2.2f));
	#endif

	LightmapColor *= pow(LightmapColor, vec3(1.0f / 2.2f));
	
	#if ENABLE_SHADOW == 1
	ShadowColor = mix(vec3(1.15) * pow(vec3(SHADOW_TRANSPARENCY / 0.5), vec3(1.0f / 2.2f)), vec3(1.15), state);
	ShadowColor = mix(ShadowColor, vec3(1), swapDayNight(worldTime));
	lowp vec3 colorRainDayOrNight = mix(vec3(0.2), vec3(1), state);
	ShadowColor = mix(ShadowColor, colorRainDayOrNight, rainStrength);
	ShadowColor *= AdjustLightmap(LightmapCoords).g;
	ShadowColor += SHADOW_TRANSPARENCY;
	#endif
	
	lowp vec3 Diffuse = col.rgb * (LightmapColor + lightBrightnessV * ShadowColor);
	Diffuse = clamp(Diffuse, 0, 1);
	col.rgb = Diffuse;
	
	float distanceFromCamera = distance(vec3(0), playerPos);
	float dhBlend = clamp((distanceFromCamera - dhNearPlane) / (dhFarPlane - distanceFromCamera), 0, 1);
    col.rgb = mix(col.rgb, fogColor, dhBlend);
	
    gl_FragData[0] = col;
}
