#version 330 compatibility

#include "/library/pad.glsl"
#include "/library/distort.glsl"

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
uniform float nightVision;

in float mask;
in vec2 lmcoord;
in vec2 texcoord;
in vec3 normal;
in vec4 glcolor;
in vec3 viewPos;

const vec3 sunlightColor = vec3(1.0, 0.3, 0.1) * 0.7;
const vec3 skylightColor = vec3(1.0, 0.25, 0.8) * 0.7;
const vec3 blocklightColor = vec3(1.0, 0.6, 0.4) * 0.7;
const vec3 ambientColor = vec3(0.1);

#define SHADOW_QUALITY 9 // [1 9 25]
#define SHADOW_RESOLUTION 1024 // [256 512 1024 2048 4096]
const int shadowMapResolution = SHADOW_RESOLUTION;
const float shadowDistanceRenderMul = 1.0;

/* RENDERTARGETS: 0,1,2,3,5 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 packLight;
layout(location = 2) out vec4 packNormal;
layout(location = 3) out vec4 packMask;
layout(location = 4) out vec4 packSpecular;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	if (abs(mask - 11.0) > 0.1 && color.a < 0.1) discard;

	if (abs(mask - 5.0) < 0.1) color = vec4(1.0, 1.0, 1.0, 0.2);
	if (abs(mask - 8.0) < 0.1) color.rgb *= vec3(2.0, 1.0, 5.0) * 0.5;

	vec3 worldNormal = normalize(normal);
	vec3 lightVector = normalize(shadowLightPosition);
	vec3 worldLightVector = mat3(gbufferModelViewInverse) * lightVector;

	vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

	vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos + worldNormal * 0.1, 1.0)).xyz;
	vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
	shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
	vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
	vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;

	float z = shadowScreenPos.z;
	float bias = (abs(mask - 1.0) < 0.1) ? 0.001 : 0.0005;
	if (abs(mask - 11.0) < 0.1 || abs(mask - 12.0) < 0.1 || abs(mask - 13.0) < 0.1 || abs(mask - 14.0) < 0.1) bias = 0.005;

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

	if (shadowScreenPos.x < 0.0 || shadowScreenPos.x > 1.0 ||
		shadowScreenPos.y < 0.0 || shadowScreenPos.y > 1.0 ||
		shadowScreenPos.z < 0.0 || shadowScreenPos.z > 1.0) {
		shadow = 1.0;
	}

	if (mask == -1.0) shadow = smoothstep(shadow, 0.0, 0.15);

	float nightvis = nightVision;

	vec2 lm = lmcoord - vec2(0.04);
	lm = clamp(vec2(1.0), vec2(0.0), lm);

	vec3 skylight = lm.g * skylightColor;
	vec3 blocklight = lm.r * blocklightColor;
	vec3 ambient = ambientColor + vec3(0.2, 0.22, 0.25) * nightvis;

	vec3 sunlight = sunlightColor * clamp(dot(worldLightVector, worldNormal), 0.2, 1.0) * shadow * mix(0.25, 1.0, 1.0 - rainStrength) * lm.g;

	color.rgb *= blocklight + skylight + ambient + sunlight;

	vec3 worldViewDir = normalize(feetPlayerPos);
	vec3 worldHalfVec = normalize(worldLightVector - worldViewDir);
	float specular = pow(max(dot(worldNormal, worldHalfVec), 0.0), 100.0);

	packLight = vec4(lm, 0.0, 1.0);
	packNormal = vec4(worldNormal * 0.5 + 0.5, 1.0);
	packMask = vec4(mask, 0.0, 0.0, 1.0);
	packSpecular = vec4(sunlightColor * specular * shadow * (1.1 - rainStrength), 1.0) * lm.g;
}