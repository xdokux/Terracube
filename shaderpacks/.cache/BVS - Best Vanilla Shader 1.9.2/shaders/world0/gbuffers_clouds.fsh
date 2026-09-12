#version 130

in vec2 TexCoords;
in vec4 Color;
in vec3 Normal;
uniform vec3 skyColor;

uniform float near, far;
uniform sampler2D texture;

void main(){
    vec4 albedo = texture2D(texture, TexCoords) * Color;
	albedo.a *= 0.6;
	
	float fog;
    fog = clamp((gl_FogFragCoord - far) * (near * 0.1), 0.0f, 1.0f);
	if(gl_Fog.color.rgb != vec3(0.0f))
	{
		albedo.a = mix(albedo.a, 0, fog);
	}
	
    /* DRAWBUFFERS:0 */
    gl_FragData[0] = albedo;
}
