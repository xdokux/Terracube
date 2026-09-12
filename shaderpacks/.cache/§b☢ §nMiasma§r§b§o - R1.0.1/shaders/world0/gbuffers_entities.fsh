#version 130

uniform sampler2D texture;

uniform int isEyeInWater;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;
uniform vec4 entityColor;

in vec2 lmcoord;
in vec2 texcoord;
in vec3 Normal;
in vec4 color;

void main() {
	vec4 albedo = texture2D(texture, texcoord) * color;
	
	albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
	albedo.rgb = mix(albedo.rgb, vec3(1, 0.58, 0.73), 0.1);
	
	vec3 shadowLightDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
	float lightBrightness = clamp(dot(shadowLightDir, Normal), 0.0f, 1.0f);
	lightBrightness = pow(lightBrightness, 0.15);
	
	/* DRAWBUFFERS:03 */
	gl_FragData[0] = albedo;
    gl_FragData[1] = vec4(lightBrightness, lmcoord, 1);
}
