#version 430 compatibility
// Vanilla Shader - Iris Version by racxusdev - racxudev.blogspot.com

uniform sampler2D depthtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D noisetex;

uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;

in vec2 texcoord;

#include "/lib/settings.glsl"
#include "/lib/distort.glsl"
#include "/lib/cave_lighting.glsl"
#include "/lib/sky.glsl"

// ============================================
// INCLUDES PARA SOMBRAS DE BLOCOS
// ============================================
#include "/lib/blocklight_shadow.glsl"

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

const vec3 blocklightColor = vec3(1.0, 0.85, 0.6) * BLOCKLIGHT_I;
const vec3 skylightColor = vec3(0.05, 0.15, 0.3) * SKYLIGHT_I;
const vec3 skylightNight = vec3(0.005, 0.008, 0.015) * SKYLIGHT_I;
const vec3 sunlightColor = vec3(1.0) * SUNLIGHT_I;
const vec3 moonlightColor = vec3(0.04, 0.05, 0.08) * MOONLIGHT_I;
const vec3 ambientColor = vec3(0.1) * AMBIENT_I;
const vec3 ambientNight = vec3(0.02) * AMBIENT_NIGHT_I;

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position){
	vec4 homPos = projectionMatrix * vec4(position, 1.0);
	return homPos.xyz / homPos.w;
}

vec3 getShadow(vec3 shadowScreenPos){
  float transparentShadow = step(shadowScreenPos.z, texture(shadowtex0, shadowScreenPos.xy).r);
  if(transparentShadow == 1.0){
    return vec3(1.0);
  }
  float opaqueShadow = step(shadowScreenPos.z, texture(shadowtex1, shadowScreenPos.xy).r);
  if(opaqueShadow == 0.0){
    return vec3(0.0);
  }
  vec4 shadowColor = texture(shadowcolor0, shadowScreenPos.xy);
  return shadowColor.rgb * (1.0 - shadowColor.a);
}

#include "/lib/vogel_shadow.glsl"

vec3 ReconstructNormal(vec2 coord, vec3 viewCenter) {
    vec2 pixelStep = 1.0 / vec2(viewWidth, viewHeight);
    float linZ = -viewCenter.z;

    float eZ = texture(depthtex0, coord + vec2(pixelStep.x, 0.0)).r;
    float wZ = texture(depthtex0, coord - vec2(pixelStep.x, 0.0)).r;
    float nZ = texture(depthtex0, coord + vec2(0.0, pixelStep.y)).r;
    float sZ = texture(depthtex0, coord - vec2(0.0, pixelStep.y)).r;

    vec3 ePos = projectAndDivide(gbufferProjectionInverse, vec3(coord + vec2(pixelStep.x, 0.0), eZ) * 2.0 - 1.0);
    vec3 wPos = projectAndDivide(gbufferProjectionInverse, vec3(coord - vec2(pixelStep.x, 0.0), wZ) * 2.0 - 1.0);
    vec3 nPos = projectAndDivide(gbufferProjectionInverse, vec3(coord + vec2(0.0, pixelStep.y), nZ) * 2.0 - 1.0);
    vec3 sPos = projectAndDivide(gbufferProjectionInverse, vec3(coord - vec2(0.0, pixelStep.y), sZ) * 2.0 - 1.0);

    float eLinZ = -ePos.z;
    float wLinZ = -wPos.z;
    bool useE = abs(eLinZ - linZ) < abs(wLinZ - linZ);
    vec3 hDeriv = useE ? normalize(ePos - viewCenter) : normalize(viewCenter - wPos);

    float nLinZ = -nPos.z;
    float sLinZ = -sPos.z;
    bool useN = abs(nLinZ - linZ) < abs(sLinZ - linZ);
    vec3 vDeriv = useN ? normalize(nPos - viewCenter) : normalize(viewCenter - sPos);

    return normalize(cross(hDeriv, vDeriv));
}

void main() {
	color = texture(colortex0, texcoord);
	color.rgb = pow(color.rgb, vec3(2.2));
	float depth = texture(depthtex0, texcoord).r;
	if (depth == 1.0) {
		vec3 NDCPos_sky = vec3(texcoord.xy, depth) * 2.0 - 1.0;
		vec3 viewPos_sky = projectAndDivide(gbufferProjectionInverse, NDCPos_sky);
		vec3 cameraPos_sky = gbufferModelViewInverse[3].xyz;
		vec3 worldSunVec_sky = mat3(gbufferModelViewInverse) * normalize(sunPosition);
		float nightFactor_sky = clamp(-worldSunVec_sky.y, 0.0, 1.0);
		vec3 skyColor = renderSkyWithClouds(viewPos_sky, cameraPos_sky, worldSunVec_sky, nightFactor_sky, frameTimeCounter);
		color.rgb = skyColor;
		return;
	}
	vec2 lightmap = texture(colortex1, texcoord).rg;
	vec3 encodedNormal = texture(colortex2, texcoord).rgb;
	vec3 normal = normalize((encodedNormal - 0.5) * 2.0);
	vec3 lightVector = normalize(shadowLightPosition);
	vec3 worldLightVector = mat3(gbufferModelViewInverse) * lightVector;
	vec3 sunVec = normalize(sunPosition);
	vec3 worldSunVec = mat3(gbufferModelViewInverse) * sunVec;
	float nightFactor = clamp(-worldSunVec.y, 0.0, 1.0);
	vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);

	vec3 viewNormal = ReconstructNormal(texcoord, viewPos);
	const int ssaoCount = 8;
	const vec3 ssaoSamples[8] = vec3[8](
		vec3( 0.5,  0.5,  0.5), vec3(-0.5,  0.5,  0.5),
		vec3( 0.5, -0.5,  0.5), vec3(-0.5, -0.5,  0.5),
		vec3( 1.0,  0.0,  0.3), vec3( 0.0,  1.0,  0.3),
		vec3(-1.0,  0.0,  0.3), vec3( 0.0, -1.0,  0.3)
	);
	vec3 tangent = normalize(cross(viewNormal, vec3(0.0, 1.0, 0.0)));
	if (abs(dot(tangent, viewNormal)) > 0.99) tangent = normalize(cross(viewNormal, vec3(1.0, 0.0, 0.0)));
	vec3 bitangent = cross(viewNormal, tangent);
	mat3 tbn = mat3(tangent, bitangent, viewNormal);
	float occ = 0.0;
	for (int i = 0; i < ssaoCount; i++) {
		vec3 samplePos = tbn * ssaoSamples[i];
		samplePos = viewPos + samplePos * 0.5;
		vec4 sampleClip = gbufferProjection * vec4(samplePos, 1.0);
		vec3 sampNDC = sampleClip.xyz / sampleClip.w;
		vec2 sampCoord = sampNDC.xy * 0.5 + 0.5;
		if (sampCoord.x >= 0.0 && sampCoord.x <= 1.0 && sampCoord.y >= 0.0 && sampCoord.y <= 1.0) {
			float sampDepth = texture(depthtex0, sampCoord).r;
			vec3 sampViewPos = projectAndDivide(gbufferProjectionInverse, vec3(sampCoord, sampDepth) * 2.0 - 1.0);
			float rangeCheck = smoothstep(0.0, 1.0, 0.5 / abs(viewPos.z - sampViewPos.z));
			occ += rangeCheck * step(sampViewPos.z, samplePos.z);
		}
	}
	occ = 1.0 - occ / float(ssaoCount);
	occ = pow(occ, 1.5);

	vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
	vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
	vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
	vec3 shadow = getSoftShadow(shadowClipPos, nightFactor, texcoord);

	// ============================================
	// LUZ NORMAL (SOL/LUA)
	// ============================================
	vec3 blocklight = lightmap.r * blocklightColor;
	vec3 skylight = lightmap.g * mix(skylightColor, skylightNight, nightFactor);
	vec3 ambient = mix(ambientColor, ambientNight, nightFactor);
	vec3 sunlight = mix(sunlightColor, moonlightColor, nightFactor) * clamp(dot(worldLightVector, normal), 0.0, 1.0) * shadow;

	// ============================================
	// SOMBRAS DE LUZ DE BLOCO (com oclusão)
	// ============================================
	vec3 blockLighting, maxBlockLighting;
	calculateBlockLighting(feetPlayerPos, normal, blockLighting, maxBlockLighting);

	// Razão de oclusão: 1 = totalmente visível, 0 = totalmente ocluído
	float maxLen = length(maxBlockLighting);
	float blockShadowFactor = maxLen > 0.001 ? length(blockLighting) / maxLen : 1.0;
	blockShadowFactor = clamp(blockShadowFactor, 0.0, 1.0);

	// Quando ocluído, reduz o lightmap do Minecraft (que ignora paredes)
	float lightmapOcclusion = mix(0.12, 1.0, blockShadowFactor);
	blocklight *= lightmapOcclusion;

	float nightDim = mix(1.0, NIGHT_DIM, nightFactor);
	float exposure = mix(EXPOSURE_DAY, EXPOSURE_NIGHT, nightFactor);
	vec3 ambientLight = (skylight + ambient) * nightDim;
	vec3 directLight = sunlight;
	float aoFactor = 1.0 - occ * 0.08;
	vec3 totalLight = (blocklight + ambientLight * aoFactor + directLight) * exposure;
	color.rgb *= totalLight;

	// Adiciona a luz de bloco com sombra (additiva)
	float blockLightIntensity = 0.6;
	color.rgb += blockLighting * blockLightIntensity;

	// ============================================
	// SPECULAR
	// ============================================
	vec3 viewDir = normalize(-viewPos);
	vec3 worldViewDir = mat3(gbufferModelViewInverse) * viewDir;
	vec3 halfVec = normalize(worldLightVector + worldViewDir);
	float spec = pow(max(dot(normal, halfVec), 0.0), SPECULAR_POWER);
	color.rgb += spec * sunlight * SPECULAR_INTENSITY;

	// ============================================
	// CAVERNAS
	// ============================================
	float dither = interleavedGradientNoise(texcoord * vec2(viewWidth, viewHeight)) * (1.0 / 256.0);
	float maxLight = max(lightmap.g, lightmap.r);
	float caveDarkness = 1.0 - smoothstep(0.0, CAVE_THRESHOLD, maxLight + dither);
	caveDarkness = pow(caveDarkness, CAVE_POWER);
	color.rgb = mix(color.rgb, vec3(0.0), caveDarkness * CAVE_STRENGTH);

	float nightDarkness = nightFactor * (1.0 - smoothstep(0.0, NIGHT_CAVE_THRESHOLD, lightmap.r + dither));
	nightDarkness = pow(nightDarkness, NIGHT_CAVE_POWER);
	color.rgb = mix(color.rgb, vec3(0.0), nightDarkness * NIGHT_CAVE_STRENGTH);
}
