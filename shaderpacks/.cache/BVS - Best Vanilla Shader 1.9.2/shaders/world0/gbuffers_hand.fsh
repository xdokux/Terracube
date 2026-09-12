#version 130

varying vec2 TexCoords;
varying vec2 LightmapCoords;
varying vec3 Normal;
varying vec4 Color;

uniform sampler2D texture;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;

void main(){
    vec4 albedo = texture2D(texture, TexCoords) * Color;
	
	vec3 shadowLightDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
	float diffuseLight = 0.0f;
	
	diffuseLight = 0.75f * clamp(4.0f * dot(Normal, normalize(sunPosition)), 0.0f, 1.0f) + 0.05;
	
    /* DRAWBUFFERS:02 */
    gl_FragData[0] = albedo;
    gl_FragData[1] = vec4(LightmapCoords, diffuseLight, 1.0f);
}
