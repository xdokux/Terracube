#version 130

#include "/lib/whatTime.glsl"

in vec2 TexCoords;

uniform int worldTime;
uniform sampler2D texture;
uniform float rainStrength;

float timeCounter;

void main(){
	vec4 albedo;
	timeCounter = smoothTransition(worldTime);
	
	albedo.r = 0.5f;
	albedo.a = texture2D(texture, TexCoords).a;
	albedo.a *= 0.35f * rainStrength;
	
    /* DRAWBUFFERS:4 */
	gl_FragData[0] = albedo;
}
