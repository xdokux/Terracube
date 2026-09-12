#version 130

#include "/settings.glsl"

in vec2 TexCoords;
in vec2 LightmapCoords;
in vec3 foliageColor;
in vec3 tangent;
in vec3 viewSpaceGeoNormal;
in vec3 viewSpacePosition;
in vec3 Normal;

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform int isEyeInWater;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;

uniform mat4 gbufferModelViewInverse;

mat3 tbnNormalTangent(vec3 normal, vec3 tangent) {
    vec3 bitangent = normalize(cross(tangent,normal));
    return mat3(tangent, bitangent, normal);
}

void main() {
    vec4 outputColorData = texture2D(gtexture, TexCoords);
	vec3 albedo = outputColorData.rgb * foliageColor;
	float lightBrightness = 0.0f;
	
	vec2 LC = LightmapCoords;
	if(isEyeInWater == 1) {
		LC += vec2(0.2f);
	}
	else if (isEyeInWater == 2) {
		albedo = vec3(0.6, 0.1, 0.0);
	}
	
	vec3 shadowLightDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
	#if PBR == 1
	vec3 viewSpaceInitialTangent = tangent.xyz;
	vec3 viewSpaceTangent = normalize(viewSpaceInitialTangent - dot(viewSpaceInitialTangent, viewSpaceGeoNormal) * viewSpaceGeoNormal);
	
	vec4 normalData = texture2D(normals,TexCoords) * 2.0 - 1.0;
	vec3 normalNormalSpace = vec3(normalData.xy,sqrt(1.0 - dot(normalData.xy, normalData.xy)));
	mat3 TBN = tbnNormalTangent(viewSpaceGeoNormal, viewSpaceTangent);
	vec3 normalViewSpace = TBN * normalNormalSpace;
	vec3 normalWorldSpace = mat3(gbufferModelViewInverse) * normalViewSpace;

	float perceptualSmoothness = texture2D(specular, TexCoords).r;
	float roughness = pow(1.0 - perceptualSmoothness, 2.0);
	float smoothness = 1 - roughness;
	
	vec3 fragFeetPlayerSpace = (gbufferModelViewInverse * vec4(viewSpacePosition, 1.0)).xyz;
	vec3 fragWorldSpace = fragFeetPlayerSpace + cameraPosition;
	
	vec3 reflectionDir = reflect(-shadowLightDir, normalWorldSpace);
	vec3 viewDir = normalize(cameraPosition - fragWorldSpace);
	
	float diffuseLight = roughness * clamp(dot(shadowLightDir, normalWorldSpace), 0.0f, 1.0f);
	float shininess = (1 + (smoothness) * 50);
	float specularLight = clamp(smoothness * pow(dot(reflectionDir, viewDir), shininess), 0.0, 1.0) * 2;
	lightBrightness = diffuseLight + specularLight;
	#else
	lightBrightness = clamp(dot(shadowLightDir, Normal), 0.0f, 1.0f);
	#endif
	
    /* DRAWBUFFERS:024 */
    gl_FragData[0] = vec4(albedo, outputColorData.a);
    gl_FragData[1] = vec4(LC, lightBrightness, 1.0f);
    gl_FragData[2] = vec4(viewSpaceGeoNormal * 0.5 + 0.5, 1.0f);
}
