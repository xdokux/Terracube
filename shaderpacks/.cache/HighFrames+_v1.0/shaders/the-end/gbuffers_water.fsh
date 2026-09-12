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

uniform float rainStrength;

in float mask;
in vec2 lmcoord;
in vec2 texcoord;
in vec3 normal;
in vec4 glcolor;
in vec3 viewPos;

const vec3 blocklightColor = vec3(1.0, 0.6, 0.25);
const vec3 skylightColor = vec3(0.3, 0.325, 0.35) * 2.0;
const vec3 sunlightColor = vec3(1.0, 0.8, 0.6) * 1.0;
const vec3 ambientColor = vec3(0.1);

#define SHADOW_RESOLUTION 1024 // [256 512 1024 2048 4096]
const int shadowMapResolution = SHADOW_RESOLUTION;
const float shadowDistanceRenderMul = 1.0;

/* RENDERTARGETS: 0,1,2,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 packLight;
layout(location = 2) out vec4 packNormal;
layout(location = 3) out vec4 packMask;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	if (color.a < 0.1) discard;

	if (abs(mask - 5.0) < 0.1) color = vec4(1.0, 1.0, 1.0, 0.5);

	vec3 worldNormal = normalize(normal);
	vec3 lightVector = normalize(shadowLightPosition);
	vec3 worldLightVector = mat3(gbufferModelViewInverse) * lightVector;

	vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

	vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos + worldNormal * 0.01, 1.0)).xyz;
	vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
	shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
	vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
	vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;

	vec2 ts = 1.0 / vec2(shadowMapResolution);
	vec2 p = shadowScreenPos.xy * shadowMapResolution - 0.5;
	vec2 f = fract(p);
	vec2 base = floor(p) * ts;

	float z = shadowScreenPos.z;
	float bias = 0.0005;

	float v1 = smoothstep(z - bias, z, texture(shadowtex0, base).r);
	float v2 = smoothstep(z - bias, z, texture(shadowtex0, base + vec2(ts.x, 0.0)).r);
	float v3 = smoothstep(z - bias, z, texture(shadowtex0, base + vec2(0.0, ts.y)).r);
	float v4 = smoothstep(z - bias, z, texture(shadowtex0, base + ts).r);

	float shadow = mix(mix(v1, v2, f.x), mix(v3, v4, f.x), f.y);

	vec3 skylight = lmcoord.g * skylightColor;
	vec3 blocklight = lmcoord.r * blocklightColor;
	vec3 ambient = ambientColor;

	vec3 sunlight = sunlightColor * clamp(dot(worldLightVector, worldNormal), 0.2, 1.0) * lmcoord.g * shadow * mix(0.25, 1.0, 1.0 - rainStrength);

	color.rgb *= blocklight + skylight + ambient + sunlight;
	packLight = vec4(lmcoord, 0.0, 1.0);
	packNormal = vec4(normal * 0.5 + 0.5, 1.0);
	packMask = vec4(mask, 0.0, 0.0, 1.0);
}