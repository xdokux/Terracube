#version 130

#include "/settings.glsl"

uniform sampler2D lightmap;
uniform float viewWidth, viewHeight;
uniform mat4 gbufferModelViewInverse;
uniform int entityId;


out vec2 lmcoord;
out vec2 texcoord;
out vec3 Normal;
out vec4 color;

const vec3 lightPos = vec3(0.16169041669088866, 0.8084520834544432, -0.5659164584181102);
const float ambientBrightness = 0.4f;
const float lightBrightness = 0.6f;

#include "/lib/jitter.glsl"

void main() {
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	color = gl_Color;
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	
	Normal = gl_Normal;
	
	if(entityId != 10000) {
		vec3 normal = gl_NormalMatrix * gl_Normal;
		normal = (gbufferModelViewInverse * vec4(normal, 0.0f)).xyz;
		
		float light = ambientBrightness;
		
		light += clamp(dot(vec3(lightPos.x, lightPos.y, lightPos.z), normal), 0.0f, 1.0f) * lightBrightness;
		light += clamp(dot(vec3(-lightPos.x, lightPos.y, -lightPos.z), normal), 0.0f, 1.0f) * lightBrightness;
		
		light = clamp(light, 0.0f, 1.0f);
		
		color.rgb *= light;
		color.rgb = clamp(color.rgb, 0.0f, 1.0f);
	}
	
	gl_Position = ftransform();
	#if TYPE_AA == 1
	gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
	#endif
}
