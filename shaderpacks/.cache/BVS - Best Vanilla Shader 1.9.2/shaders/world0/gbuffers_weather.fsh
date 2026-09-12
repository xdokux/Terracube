#version 130

in vec2 TexCoords;
in vec4 Color;

uniform sampler2D texture;
uniform float rainStrength;

void main(){
	vec4 albedo = vec4(0.0);
	
	albedo.a = texture2D(texture, TexCoords).a;
	
	if (albedo.a > 0.001) {
		albedo.rgb = texture2D(texture, TexCoords).rgb;

		albedo.a *= 0.45 * rainStrength * length(albedo.rgb / 3.0) * float(albedo.a > 0.1);
		albedo.rgb = sqrt(albedo.rgb);
		albedo.rgb *= vec3(0.43, 0.63, 0.81);

		#if MC_VERSION < 10800
		albedo.a *= 4.0;
		albedo.rgb *= 0.525;
		#endif
		
		#if ALPHA_BLEND == 0
		albedo.rgb = sqrt(max(albedo.rgb, vec3(0.0)));
		albedo.a *= 2;
		#endif
	}
	
    /* DRAWBUFFERS:0 */
	gl_FragData[0] = albedo;
}
