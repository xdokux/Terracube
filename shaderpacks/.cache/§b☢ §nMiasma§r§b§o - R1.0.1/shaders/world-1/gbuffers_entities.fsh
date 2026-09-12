#version 130

uniform sampler2D texture;

uniform vec4 entityColor;

in vec2 texcoord;
in vec4 color;

void main() {
	vec4 albedo = texture2D(texture, texcoord) * color;
	
	albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
	albedo.rgb = mix(albedo.rgb, vec3(1, 0.58, 0.73), 0.1);
	
	gl_FragData[0] = albedo;
}
