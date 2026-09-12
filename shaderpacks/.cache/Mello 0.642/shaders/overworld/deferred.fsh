#version 330 compatibility

#include "/library/pad.glsl"
#include "/library/distort.glsl"
#include "/library/time.glsl"
#include "/program/material.glsl"
#include "/library/bluenoise.glsl"

uniform sampler2D shadowtex0;
uniform sampler2D depthtex1;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;

uniform vec3 shadowLightPosition;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform float viewWidth;
uniform float viewHeight;

uniform float rainStrength;
uniform float nightVision;

float foliage;
float size;
float strength;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

const vec3 blocklightColor = vec3(1.0, 0.6, 0.4) * 0.7;
const vec3 ambientColor = vec3(0.1);

#define SHADOW_QUALITY 9 // [1 9 25]
#define SHADOW_RESOLUTION 1024 // [256 512 1024 2048 4096]
#define SHADOW_DISTANCE 150 // [25 50 100 150 200 250 300]

const int shadowMapResolution = SHADOW_RESOLUTION;
const float shadowDistanceRenderMul = 1.0;
const float shadowDistance = SHADOW_DISTANCE;

void main() {
	color = texture(colortex0, texcoord);
	float depth = texture(depthtex1, texcoord).r;
	float mask = texture(colortex3, texcoord).r;
	if (depth == 1.0 || abs(mask - 9.0) < 0.1) return;

	vec2 lightmap = texture(colortex1, texcoord).rg - 0.04;
	lightmap = clamp(vec2(1.0), vec2(0.0), lightmap);

	vec3 encodedNormal = texture(colortex2, texcoord).rgb;
	vec3 normal = normalize((encodedNormal - 0.5) * 2.0);

	vec3 lightVector = normalize(shadowLightPosition);
	vec3 worldLightVector = mat3(gbufferModelViewInverse) * lightVector;

	vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
	vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
	vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos + normal * 0.1, 1.0)).xyz;
	vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
	shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
	vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
	vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;

	float z = shadowScreenPos.z;
	float bias = (abs(mask - 1.0) < 0.1 || abs(mask - 19.0) < 0.1) ? 0.001 : 0.0005;
	if (abs(mask - 11.0) < 0.1 || abs(mask - 12.0) < 0.1 || abs(mask - 26.0) < 0.1 || abs(mask - 13.0) < 0.1 || abs(mask - 14.0) < 0.1) bias = 0.005;
	float farFactor = clamp(length(viewPos) / 128.0, 0.0, 1.0);
	bias += farFactor * 0.005;

	ivec2 screenCoord = ivec2(gl_FragCoord.xy);
	float noise = getNoise(uvec2(screenCoord));

	float theta = noise * 6.2831853;
	mat2 rotation = mat2(cos(theta), -sin(theta), sin(theta), cos(theta));

	float shadow = 0.0;
	int range = int(sqrt(float(SHADOW_QUALITY))) / 2;

	for (int x = -range; x <= range; x++) {
		for (int y = -range; y <= range; y++) {
			vec2 offset = vec2(float(x), float(y));
			
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

	calculateTimeBlend();

	float nightvis = nightVision;

	vec3 skylight = lightmap.g * getSkyLightColor();
	vec3 blocklight = lightmap.r * blocklightColor;
	vec3 ambient = ambientColor + vec3(0.2, 0.22, 0.25) * nightvis;

	getMaterial(mask, foliage, size, strength);

	vec3 sunlight = getPointLightColor() * clamp(dot(worldLightVector, normal) * 0.85 + 0.15, foliage, 1.0) * shadow * mix(0.25, 1.0, 1.0 - rainStrength) * lightmap.g;
	
	float specular = pow(max(dot(normal, normalize(worldLightVector - normalize(feetPlayerPos))), 0.0), size) * lightmap.g;

	float gray = dot(texture(colortex0, texcoord).rgb, vec3(0.299, 0.587, 0.114));
	strength *= clamp(gray, 0.5, 1.0);

	color.rgb *= blocklight + skylight + ambient + sunlight;
	color.rgb += getPointLightColor() * specular * shadow * strength * (1.1 - rainStrength) * clamp(dot(worldLightVector, normal), foliage, 1.0);
}