#version 130

in vec2 TexCoords;
in vec2 LightmapCoords;
in vec3 Normal;
in vec4 Color;

uniform sampler2D texture;

void main(){
    vec4 albedo = texture2D(texture, TexCoords);
	albedo.rgb *= Color.rgb;
	
    /* DRAWBUFFERS:024 */
	gl_FragData[0] = albedo;
    gl_FragData[1] = vec4(LightmapCoords, 0.0f, 1.0f);
    gl_FragData[2] = vec4(Normal * 0.5 + 0.5, 1.0f);
}
