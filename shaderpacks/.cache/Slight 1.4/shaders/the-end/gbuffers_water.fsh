#version 330 compatibility

#include "/library/pad.glsl"
#include "/library/distort.glsl"
#include "/library/time.glsl"

uniform sampler2D gtexture;
uniform sampler2D shadowtex0;

uniform vec3 shadowLightPosition;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform sampler2D blueNoiseTex;
uniform float viewWidth;
uniform float viewHeight;

uniform float rainStrength;

in float mask;
in vec2 lmcoord;
in vec2 texcoord;
in vec3 normal;
in vec4 glcolor;
in vec3 viewPos;

const vec3 blocklightColor = vec3(1.0, 0.5, 0.25);
const vec3 skylightColor = vec3(0.3, 0.1, 0.3) * 2.0;
const vec3 sunlightColor = vec3(1.0, 0.5, 0.3) * 0.5;
const vec3 ambientColor = vec3(0.1, 0.05, 0.1);

#define SHADOW_QUALITY 9 // [1 9 25]
#define SHADOW_RESOLUTION 1024 // [256 512 1024 2048 4096]
const int shadowMapResolution = SHADOW_RESOLUTION;
const float shadowDistanceRenderMul = 1.0;

/* RENDERTARGETS: 0,1,2,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 packLight;
layout(location = 2) out vec4 packNormal;
layout(location = 3) out vec4 packMask;

uniform float frameTimeCounter;
uniform vec3 cameraPosition;

#define WATER_WAVE_STRENGTH 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

float hash12(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float waveNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	if (color.a < 0.1) discard;

	if (abs(mask - 5.0) < 0.1) color = vec4(1.0, 1.0, 1.0, 0.2);

	vec3 worldNormal = normalize(normal);
	vec3 lightVector = normalize(shadowLightPosition);
	vec3 worldLightVector = mat3(gbufferModelViewInverse) * lightVector;

	vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

	vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos + worldNormal * 0.05, 1.0)).xyz;
	vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
	shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
	vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
	vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;

	float z = shadowScreenPos.z;
	float bias = (abs(mask - 1.0) < 0.1) ? 0.001 : 0.0005;

	ivec2 screenCoord = ivec2(texcoord * vec2(viewWidth, viewHeight));
	ivec2 noiseCoord = screenCoord % 64;
	float noise = texelFetch(blueNoiseTex, noiseCoord, 0).r;

	float theta = noise * 6.2831853;
	mat2 rotation = mat2(cos(theta), -sin(theta), sin(theta), cos(theta));

	float shadow = 0.0;
	int range = int(sqrt(float(SHADOW_QUALITY))) / 2;

	for (int x = -range; x <= range; x++) {
		for (int y = -range; y <= range; y++) {
			vec2 offset = vec2(float(x), float(y)) * 1.5;
			
			offset = rotation * offset; 
			
			vec2 offsetCoord = shadowScreenPos.xy + (offset / float(shadowMapResolution));
			shadow += smoothstep(z - bias, z, texture(shadowtex0, offsetCoord).r);
		}
	}
	shadow /= float(SHADOW_QUALITY);

	vec3 packedNormal = worldNormal;
	if (abs(mask - 5.0) < 0.1 && WATER_WAVE_STRENGTH > 0.0) {
		vec3 worldPos = feetPlayerPos + cameraPosition;
		vec2 p = worldPos.xz * 0.5;
		float t = frameTimeCounter;
		p += vec2(t);

		float n  = waveNoise(p);
		float n2 = waveNoise(p * 1.7 + 4.0 - vec2(t * 0.5, t * 0.3));
		vec2 offset = vec2(n, n2) * 2.0 - 1.0;

		float light = lmcoord.g * lmcoord.g;
		packedNormal.xz += offset * 0.03 * WATER_WAVE_STRENGTH * light;
		packedNormal = normalize(packedNormal);
	}

	vec3 skylight = lmcoord.g * skylightColor;
	vec3 blocklight = lmcoord.r * blocklightColor;
	vec3 ambient = ambientColor;

	vec3 sunlight = sunlightColor * clamp(dot(worldLightVector, packedNormal), 0.2, 1.0) * lmcoord.g * shadow * mix(0.25, 1.0, 1.0 - rainStrength);

	color.rgb *= blocklight + skylight + ambient + sunlight;

	vec3 worldViewDir = normalize(feetPlayerPos);
	vec3 worldHalfVec = normalize(worldLightVector - worldViewDir);
	float specular = pow(max(dot(packedNormal, worldHalfVec), 0.0), 32.0);

	color.rgb += vec3(1.0, 0.3, 0.5) * specular * shadow * 2.0 * (1.1 - rainStrength);

	packLight = vec4(lmcoord, 0.0, 1.0);
	packNormal = vec4(packedNormal * 0.5 + 0.5, 1.0);
	packMask = vec4(mask, 0.0, 0.0, 1.0);
}