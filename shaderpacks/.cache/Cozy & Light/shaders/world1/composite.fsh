#version 330 compatibility

#define SSR_ENABLED

uniform sampler2D gtexture;
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

in vec2 texcoord;

#include "/world1/lib_world1.glsl"

/* DRAWBUFFERS: 0 */
layout(location = 0) out vec4 outColor0;

float LinearDepth(float z) {
    return 1.0 / ((1 - far / near) * z + (far / near));
}

float luminosity(vec3 color) {
	return dot(color, vec3(0.213, 0.715, 0.072));
}

void main() {
	vec4 color = texture(colortex0, texcoord);

	color.rgb = pow(color.rgb, vec3(2.2));

	float water = texture(colortex4, texcoord).r;

	vec3 debug = vec3(0.0);

	if(water >= 0.1) {

		float depth = texture(depthtex0, texcoord).r;
		float lineardepth0 = LinearDepth(depth);
		float lineardepth1 = LinearDepth(texture(depthtex1, texcoord).r);

		// Water fog
		if(isEyeInWater == 0.0) {
			//color.rgb *= waterTint;
			vec3 densities = GetFogDensities(1);

			vec3 fogFactors = exp(-densities * (lineardepth1 - lineardepth0));

			color.rgb = mix(color.rgb, GetLightColor(1), pow(1.0 - fogFactors, vec3(2.0)));
			//color.rgb = vec3(lineardepth1);
		}

		vec3 normal = texture(colortex1, texcoord).xyz * 2.0 - 1.0;
		vec3 screenPos = vec3(texcoord, depth);
		vec3 eyePos = ViewPosToEyePos(ScreenPosToViewPos(screenPos));

		vec3 rayDir = normalize(eyePos);
		float hit = 0.0;

		float accuracy = length(eyePos) * 0.03;

		// Reflect ray
		rayDir = rayDir - 2.0 * dot(normal, rayDir) * normal;

		vec3 rayPos = eyePos + rayDir * accuracy;

		vec3 reflection = calcSkyColor(EyePosToViewPos(rayDir));
	
	#ifdef SSR_ENABLED
		// Ray marching SSR
		for(int i = 0; i < 100; i++) {
			vec3 rayScreenPos = ViewPosToScreenPos(EyePosToViewPos(rayPos));

			// Check if rayPos is outside of screen
			if(rayScreenPos.x > 1.0 || rayScreenPos.x < 0.0) {
				break;
			}
			if(rayScreenPos.y > 1.0 || rayScreenPos.y < 0.0) {
				break;
			}
			if(LinearDepth(rayScreenPos.z) > 1.0) {
				break;
			}

			float rayDepth = LinearDepth(rayScreenPos.z);
			float depthAtRayPos = LinearDepth(texture(depthtex0, rayScreenPos.xy).r);

			// Check if collision
			if(rayDepth >= depthAtRayPos) {
				if(abs(rayDepth - depthAtRayPos) < 0.01) {
					// Collision within screen

					hit = 1.0;
					
					reflection = texture(colortex0, rayScreenPos.xy).rgb;
					reflection = pow(reflection, vec3(2.2));
					break;
				}
			}

			// If not march ray
			rayPos += rayDir * 0.5;
			debug = vec3(float(i/100.0));
		}
	#endif
		
		float reflectionFactor = (1.0 - abs(dot(normal, normalize(-eyePos))));
		//float reflectionBright = dot(vec3(0.2126, 0.7152, 0.0722), reflection);
		color.rgb = mix(color.rgb * waterTint, reflection, reflectionFactor);

		// Fog
		vec3 densities = GetFogDensities(isEyeInWater);
		vec3 fogFactors = (exp(-densities * lineardepth0));
		color.rgb = mix(color.rgb, GetLightColor(isEyeInWater), pow(1.0 - fogFactors, vec3(2.0)));
	}

	//outColor0 = mix(vec4(0.0, 0.0, 0.0, 1.0), vec4(reflection, 1.0), water * reflectionFactor);
	color.rgb = pow(color.rgb, vec3(1.0/2.2));
	outColor0 = color;
	//outColor0 = texture(gtexture, texcoord);
	//outColor0 = texture(colortex3, texcoord);
}