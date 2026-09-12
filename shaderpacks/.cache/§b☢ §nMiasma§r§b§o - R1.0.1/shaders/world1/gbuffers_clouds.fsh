#version 130

uniform sampler2D texture;

uniform vec3 fogColor;
uniform float far, near;
uniform int isEyeInWater;

in vec2 texcoord;
in vec4 color;
in vec3 viewPos;

void main() {
	vec4 col = texture2D(texture, texcoord) * color;
	
	
	float farW = 2048;
	float distW = 7;
	if(isEyeInWater == 1) {
		farW = 32;
		distW = 2;
	}
	
	float dist = clamp((length(viewPos) - near) / (farW - near), 0.0f, 1.0f);
	float fogFactor = exp(-distW * (1.0 - dist));
	col.a = mix(col.a, 0.0, fogFactor);
	
	
	gl_FragData[0] = col;
}
