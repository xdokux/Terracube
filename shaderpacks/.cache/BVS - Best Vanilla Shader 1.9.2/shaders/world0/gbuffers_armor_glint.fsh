#version 130

in vec2 TexCoords;
in vec2 LightmapCoords;
in vec3 Normal;
in vec4 Color;

uniform sampler2D texture;

void main(){
    vec4 albedo = texture2D(texture, TexCoords);
	albedo.rgb *= Color.rgb;
	
    /* DRAWBUFFERS:0 */
	gl_FragData[0] = albedo;
}
