#version 130

#include "/settings.glsl"

in vec4 at_tangent;

in vec3 mc_Entity;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

out vec2 TexCoords;
out vec3 foliageColor;
out vec2 LightmapCoords;
out vec3 tangent;
out vec3 viewSpaceGeoNormal;
out vec3 viewSpacePosition;
out vec3 Normal;

uniform float frameTimeCounter;
uniform int worldTime;
float state;

uniform float far;
uniform vec3 previousCameraPosition;

vec3 getPlayerPosition() {
    vec3 eyeCameraPosition = cameraPosition + gbufferModelViewInverse[3].xyz;
    vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 worldPos = feetPlayerPos + cameraPosition;
    vec3 eyePlayerPos = worldPos - eyeCameraPosition;
    return eyePlayerPos;
}

vec3 getViewPositionFromPlayerPosition(vec3 eyePlayerPos) {
    vec3 eyeCameraPosition = cameraPosition + gbufferModelViewInverse[3].xyz;
    vec3 viewPos = mat3(gbufferModelView) * eyePlayerPos;

    return viewPos;
}

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

vec3 effect() {
    vec3 position = getPlayerPosition();
    float distance_norm = length(position.xz) / far;
    distance_norm = clamp(distance_norm, 0.0, 1.0);

    float a = 0.03;
    float b = 0.05;
    float offset = (a / (distance_norm - 1)) + a + (b * pow(distance_norm, 2.0));

    position.y += (offset * 10.0);

    return getViewPositionFromPlayerPosition(position);
}

void main() {
	tangent = gl_NormalMatrix * at_tangent.xyz;

	vec3 pos;
	#if CHUNK_ANIMATION == 1
	pos = effect();
	#else
	pos = (gl_ModelViewMatrix * gl_Vertex).xyz;
	#endif
	
	#if SWAYING_FOLIAGE == 1
	if (mc_Entity.x == 10106 || mc_Entity.x == 10018) {
		vec3 position = mat3(gbufferModelViewInverse) * (gl_ModelViewMatrix * gl_Vertex).xyz + gbufferModelViewInverse[3].xyz;
		vec3 vworldpos = position.xyz + cameraPosition;
		float fy = fract(vworldpos.y - 0.1);
		float wave = 0.05 * sin(3 * 3.14 * (frameTimeCounter * 0.2 + vworldpos.x / 2.5 + vworldpos.z / 5.0))
			+ 0.05 * -sin(2 * 3.14 * (frameTimeCounter * 0.4 + vworldpos.x / 6.0 + vworldpos.z / 12.0));
		pos.y += clamp(wave, -fy, 1.0 - fy) * 0.25f;
		pos.x += clamp(wave, -fy, 1.0 - fy) * 0.35f;
		pos.z += clamp(wave, -fy, 1.0 - fy) * 0.15f;
    }
	#endif
	
    gl_Position = gl_ProjectionMatrix * vec4(pos,1);
    gl_FogFragCoord = length(pos);
	
	TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	viewSpaceGeoNormal = gl_NormalMatrix * gl_Normal;
	Normal = gl_Normal;
	
	vec3 model_pos = gl_Vertex.xyz;
	vec4 view_pos = gl_ModelViewMatrix * vec4(model_pos, 1.0);
	viewSpacePosition = view_pos.xyz;
	
    LightmapCoords = mat2(gl_TextureMatrix[1]) * gl_MultiTexCoord1.xy;
    LightmapCoords = (LightmapCoords * 33.05f / 32.0f) - (1.05f / 32.0f);
	
	#if NEW_LIGHTING == 0
	vec3 normal = gl_NormalMatrix * gl_Normal;
	//normal = (mc_Entity.x == 1) ? vec3(0,1,0) : (gbufferModelViewInverse * vec4(normal,0)).xyz;
    float light = min(normal.x * normal.x * 0.6f + normal.y * normal.y * 0.25f * (3.0f + normal.y) + normal.z * normal.z * 0.8f, 1.0f);
	#if CLASSIC_NIGHT == 0
	state = smoothTransition(worldTime);
	foliageColor = vec3((gl_Color.rgb * light * state) + (gl_Color.rgb * (1 - state) * 0.85f));
	#else
	foliageColor = vec3(gl_Color.rgb * light);
	#endif
	#else
	foliageColor = gl_Color.rgb;
	#endif
}
