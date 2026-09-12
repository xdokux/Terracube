#version 330 compatibility

#include "/library/pad.glsl"
#include "/library/distort.glsl"
#include "/library/time.glsl"

/*
const int colortex0Format = RGB16F;
*/

/*
const int colortex1Format = RG8;
*/

/*
const int colortex2Format = RGB8;
*/

/*
const int colortex3Format = R16F;
*/

/*
const int colortex4Format = RGBA16F;
*/

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

uniform sampler2D blueNoiseTex;
uniform float viewWidth;
uniform float viewHeight;

uniform float rainStrength;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

const vec3 blocklightColor = vec3(1.0, 0.5, 0.25);
const vec3 ambientColor = vec3(0.1);

#define SHADOW_QUALITY 9 // [1 9 25]
#define SHADOW_RESOLUTION 1024 // [256 512 1024 2048 4096]
const int shadowMapResolution = SHADOW_RESOLUTION;
const float shadowDistanceRenderMul = 1.0;

void main() {
	color = texture(colortex0, texcoord);
	float depth = texture(depthtex1, texcoord).r;
	if (depth == 1.0) return;

	vec2 lightmap = texture(colortex1, texcoord).rg;
	vec3 encodedNormal = texture(colortex2, texcoord).rgb;
	vec3 normal = normalize((encodedNormal - 0.5) * 2.0);
	float mask = texture(colortex3, texcoord).r;

	vec3 lightVector = normalize(shadowLightPosition);
	vec3 worldLightVector = mat3(gbufferModelViewInverse) * lightVector;

	vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
	vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
	vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos + normal * 0.05, 1.0)).xyz;
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

	calculateTimeBlend();

	vec3 skylight = lightmap.g * getSkyLightColor();
	vec3 blocklight = lightmap.r * blocklightColor;
	vec3 ambient = ambientColor;

	float foliage = 0.0;
	if (abs(mask - 1.0) < 0.1) foliage = 1.0;
	if (abs(mask - 0.5) < 0.1) foliage = 0.1;

	vec3 sunlight = getPointLightColor() * clamp(dot(worldLightVector, normal), foliage, 1.0) * lightmap.g * shadow * mix(0.25, 1.0, 1.0 - rainStrength);
	
	float size = 4.0;
	if (abs(mask - 1.0) < 0.1) size = 16.0;
	if (abs(mask - 2.0) < 0.1) size = 64.0;

	float specular = pow(max(dot(normal, normalize(worldLightVector - normalize(feetPlayerPos))), 0.0), size);

	float strength = 0.3;
	if (abs(mask - 1.0) < 0.1) strength = 0.8;
	if (abs(mask - 2.0) < 0.1) strength = 2.0;
	
	float gray = dot(texture(colortex0, texcoord).rgb, vec3(0.299, 0.587, 0.114));
	strength *= clamp(gray, 0.5, 1.0);

	color.rgb *= blocklight + skylight + ambient + sunlight;
	color.rgb += getPointLightColor() * specular * shadow * strength * (1.1 - rainStrength) * clamp(dot(worldLightVector, normal), foliage, 1.0);
}