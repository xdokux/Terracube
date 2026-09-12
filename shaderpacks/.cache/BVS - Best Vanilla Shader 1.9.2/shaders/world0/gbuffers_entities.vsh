#version 130

#include "/settings.glsl"

in vec4 at_tangent;

in vec3 mc_Entity;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

out vec2 TexCoords;
out vec4 Color;
out vec2 LightmapCoords;
out vec3 tangent;
out vec3 viewSpaceGeoNormal;
out vec3 Normal;

uniform int worldTime;
float state;

float smoothTransition(float time) {
    if (time >= 0.0f && time <= 1000.0f) {
        return time / 1000.0f;
	} else if (time > 1000.0f && time < 12000.0f) {
        return 1.0f;
    } else if (time >= 12000.0f && time <= 13000.0f) {
        return 1.0f - (time - 12000.0f) / 1000.0f;
    } else {
        return 0.0f;
    }
}

void main() {
	tangent = gl_NormalMatrix * at_tangent.xyz;

	vec3 pos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    pos = (gbufferModelViewInverse * vec4(pos,1)).xyz;
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(pos,1);
    gl_FogFragCoord = length(pos);
	
	TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	viewSpaceGeoNormal = gl_NormalMatrix * gl_Normal;
	Normal = gl_Normal;
	
    LightmapCoords = mat2(gl_TextureMatrix[1]) * gl_MultiTexCoord1.xy;
    LightmapCoords = (LightmapCoords * 33.05f / 32.0f) - (1.05f / 32.0f);
	
	#if NEW_LIGHTING == 0
	vec3 normal = gl_NormalMatrix * gl_Normal;
	normal = (mc_Entity.x == 1) ? vec3(0,1,0) : (gbufferModelViewInverse * vec4(normal,0)).xyz;
    float light = min(normal.x * normal.x * 0.6f + normal.y * normal.y * 0.25f * (3.0f + normal.y) + normal.z * normal.z * 0.8f, 1.0f);
	#if CLASSIC_NIGHT == 0
	state = smoothTransition(worldTime);
	Color = vec4((gl_Color.rgb * light * state) + (gl_Color.rgb * (1 - state) * 0.85f), gl_Color.a);
	#else
	Color = vec4(gl_Color.rgb * light, gl_Color.a);
	#endif
	#else
	Color = gl_Color;
	#endif
}
