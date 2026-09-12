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
const int colortex4Format = RGBA8;
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

uniform float sunAngle;
uniform float rainStrength;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

const vec3 blocklightColor = vec3(1.0, 0.6, 0.25);
const vec3 ambientColor = vec3(0.15);

// --- [ Shadows ] ---
#define SHADOW_RESOLUTION 4096 // [256 512 1024 2048 4096]
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
	vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos + normal * 0.02, 1.0)).xyz;
	vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
	shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
	vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
	vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;

	vec2 ts = 1.0 / vec2(shadowMapResolution);

	vec2 p = shadowScreenPos.xy * shadowMapResolution - 0.5;
	vec2 f = fract(p);
	vec2 base = floor(p) * ts;

	float z = shadowScreenPos.z;
	float bias = max(0.0005 * (1.0 - dot(normalize(shadowLightPosition), normal)), 0.0002);

	float shadow = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 offset = vec2(x, y) * ts;
			float v1 = smoothstep(z - bias, z, texture(shadowtex0, base + offset).r);
			float v2 = smoothstep(z - bias, z, texture(shadowtex0, base + offset + vec2(ts.x, 0.0)).r);
			float v3 = smoothstep(z - bias, z, texture(shadowtex0, base + offset + vec2(0.0, ts.y)).r);
			float v4 = smoothstep(z - bias, z, texture(shadowtex0, base + offset + ts).r);
			shadow += mix(mix(v1, v2, f.x), mix(v3, v4, f.x), f.y);
		}
	}
	shadow /= 9.0;

	calculateTimeBlend();

	vec3 skylight = lightmap.g * getSkyLightColor();
	vec3 blocklight = lightmap.r * blocklightColor;
	vec3 ambient = ambientColor;

	float foliage = 0.0;
	if (abs(mask - 1.0) < 0.1) foliage = 1.0;
	if (abs(mask - 0.5) < 0.1) foliage = 0.1;

	vec3 sunlight = getPointLightColor() * clamp(dot(worldLightVector, normal), foliage, 1.0) * lightmap.g * shadow * mix(0.25, 1.0, 1.0 - rainStrength);

	color.rgb *= blocklight + skylight + ambient + sunlight;
}