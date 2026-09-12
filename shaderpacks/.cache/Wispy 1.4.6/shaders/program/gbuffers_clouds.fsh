#include "/lib/all_the_libs.glsl"
#include "/global/sky.glsl"

uniform sampler2D gtexture;
varying vec2 texcoord;
varying vec4 glcolor;
varying float cloudGradient;

void main() {
	vec3 ScreenPos = vec3(gl_FragCoord.xy * resolutionInv, gl_FragCoord.z);

	#ifdef DISTANT_HORIZONS
	float DhDepth = texture2D(dhDepthTex, ScreenPos.xy).x;
	if(DhDepth < 1.0) {
		discard;
		return;
	}
	#endif

	vec4 Color = texture2D(gtexture, texcoord);
	if (Color.a < 0.1) discard;

	float topAlpha = 0.2;
	Color.a *= mix(1.0, topAlpha, cloudGradient);

	float skyBrightness = length(SKY_TOP);
	float ambientMult = clamp(skyBrightness * 1.5, 0.05, 1.0);
	float nightFactor = clamp(1.0 - skyBrightness * 4.0, 0.0, 1.0);

	vec3 dayTop = vec3(1.0, 1.0, 1.0);
	vec3 dayBottom = vec3(0.6, 0.65, 0.75);
	vec3 nightTop = vec3(0.15, 0.18, 0.25);
	vec3 nightBottom = vec3(0.02, 0.03, 0.06);

	vec3 lightCloudTop = mix(dayTop * ambientMult, nightTop, nightFactor);
	vec3 darkCloudBottom = mix(dayBottom * (ambientMult * 0.7), nightBottom, nightFactor);

	vec3 gradientColor = mix(darkCloudBottom, lightCloudTop, cloudGradient);

	float boost = 1.0 + (cloudGradient * 0.5);
	Color.rgb *= gradientColor * boost;
	Color.rgb = to_linear(Color.rgb) * 2.5;

	#ifdef BORDER_FOG
	vec3 ViewPos = to_view_pos(ScreenPos, false);
	vec3 PlayerPos = to_player_pos(ViewPos);
	float HorizontalDist = length(PlayerPos.xz) / far;
	float fogFactor = smoothstep(0.95, 1.0, HorizontalDist);
	Color.a *= 1.0 - fogFactor;
	Color.a *= 1.0 - max(darknessFactor, blindness);
	#endif

	/* DRAWBUFFERS:0 */
	gl_FragData[0] = Color;
}
