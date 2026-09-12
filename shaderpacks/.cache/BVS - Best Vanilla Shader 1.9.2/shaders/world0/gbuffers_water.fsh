#version 130

#include "/settings.glsl"

in vec2 TexCoords;
in vec2 LightmapCoords;
in vec3 foliageColor;
in vec3 tangent;
in vec3 viewSpaceGeoNormal;
in float blockId;

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform sampler2D noisetex;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;
uniform float frameTimeCounter;

uniform mat4 gbufferModelViewInverse;

vec2 encode (vec3 n){
    return vec2(n.xy * inversesqrt(n.z * 8.0 + 8.0) + 0.5);
}

void main(){
    vec4 outputColorData = texture2D(gtexture, TexCoords);
	vec3 albedo = outputColorData.rgb * foliageColor;
	vec3 norm = viewSpaceGeoNormal;
	float diffuseLight = 0.25;
	vec2 normalssr = vec2(0.001f);
	vec3 shadowLightDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
	
	if (int(blockId + 0.5) == 1000) {
		outputColorData.a = 0.87f;
        diffuseLight = clamp(dot(shadowLightDir, viewSpaceGeoNormal), 0.0f, 1.0f);
		
		#if SSR == 1
		vec4 noiseSample = texture2D(noisetex, (TexCoords + frameTimeCounter * 0.0005) * 16); // 512
		vec3 noiseEffect = noiseSample.rgb * 0.025;
		norm += noiseEffect;
		norm = normalize(norm);
		normalssr = encode(norm);
		#else
		normalssr.x = 1.0f;
		#endif
    }
	
    /* DRAWBUFFERS:0234 */
    gl_FragData[0] = vec4(albedo, outputColorData.a);
    gl_FragData[1] = vec4(LightmapCoords, diffuseLight, outputColorData.a);
	gl_FragData[2] = vec4(normalssr, vec2(1.0f));
	gl_FragData[3] = vec4(viewSpaceGeoNormal * 0.5 + 0.5, 1.0f);
}
