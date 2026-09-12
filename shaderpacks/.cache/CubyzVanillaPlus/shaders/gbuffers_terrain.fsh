// gbuffers_terrain.fsh
// Vanilla-plus: keeps Cubyz's own per-vertex torch/sky light, adds a real
// shadow map for direct sun/moon light plus distance fog. No PBR, no GI -
// just legible directional shading over what Cubyz already looked like.

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vcolor;

uniform vec3 shadowLightPosition;
uniform vec3 cubyz_ambientLight;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2D shadowtex0; // all casters (used for the colored/soft edge)
uniform sampler2D shadowtex1; // opaque casters only (used for the hard test)

uniform sampler2D lightmap;
uniform float far;

struct cubyz_FogParameters {vec4 color; float density; float start; float end; float scale;};
uniform cubyz_FogParameters cubyz_Fog;

/* DRAWBUFFERS:0 */

// 4-tap rotated PCF. Cheap, and enough to soften shadow-map aliasing without
// a full PCSS setup - that's a v2 upgrade once this baseline is confirmed working.
float sampleShadow(vec3 shadowClip) {
	vec2 texel = 1.0 / vec2(textureSize(shadowtex1, 0));
	float shadow = 0.0;
	vec2 offsets[4] = vec2[](vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0), vec2(1.0, 1.0));
	for (int i = 0; i < 4; i++) {
		float depthSample = texture2D(shadowtex1, shadowClip.xy + offsets[i] * texel * 0.75).r;
		shadow += step(shadowClip.z - 0.0015, depthSample);
	}
	return shadow * 0.25;
}

void main() {
	vec4 albedo = texture2D(gtexture, texcoord) * vcolor;
	if (albedo.a < 0.1) discard;

	// Cubyz's own per-vertex light: x = torch, y = sky access (see the
	// bridge's cubyz_setupVertex comment for why this isn't raw sun intensity).
	vec3 lightmapColor = texture2D(lightmap, lmcoord).rgb;

	vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

	// Shadow-space lookup for the direct sun/moon contribution only - the
	// lightmap above already carries torch and general sky access.
	vec4 shadowClip = shadowProjection * shadowModelView * vec4(worldPos, 1.0);
	shadowClip.xyz = shadowClip.xyz * 0.5 + 0.5;
	float shadow = 1.0;
	if (clamp(shadowClip.xyz, 0.0, 1.0) == shadowClip.xyz) {
		shadow = sampleShadow(shadowClip.xyz);
	}

	float NdotL = max(dot(normal, normalize(shadowLightPosition)), 0.0);
	float skyAccess = lmcoord.y;
	float direct = NdotL * shadow * skyAccess;

	vec3 ambient = cubyz_ambientLight * 0.5 + lightmapColor * 0.5;
	vec3 lit = albedo.rgb * (ambient + direct * 0.9);

	// Distance fog, tied to Cubyz's own fog parameters so it matches whatever
	// the native sky/render-distance fade is already doing.
	float dist = length(viewPos);
	float fogFactor = clamp((dist - cubyz_Fog.start) / max(cubyz_Fog.end - cubyz_Fog.start, 1.0), 0.0, 1.0);
	fogFactor *= cubyz_Fog.scale;
	vec3 finalColor = mix(lit, cubyz_Fog.color.rgb, fogFactor);

	gl_FragData[0] = vec4(finalColor, albedo.a);
}
