#version 130

in vec2 TexCoords;
in vec2 LightmapCoords;
in vec3 Normal;
in vec4 Color;

uniform sampler2D texture;

void main(){
    vec4 albedo = texture2D(texture, TexCoords) * Color;
	
    /* DRAWBUFFERS:02 */
    gl_FragData[0] = albedo;
    gl_FragData[1] = vec4(vec3(1.0f), albedo.a);
}
